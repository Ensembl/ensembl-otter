=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Evi::BlixemLauncher;

# Just launch Blixem with the slice and a set of EviChains
#
# lg4

use Hum::Conf qw{ PFETCH_SERVER_LIST }; # to get the default pfetch server and port

use Bio::Seq;               # for emitting the fasta sequence of the slice
use Bio::SeqIO;

my $remove_files  = 1;  # cleanup_after_use(=1) vs leave_for_debug(=0)
my $tmp_dir       = '.';# where to create files

my $quick_pfetch  = 1;  # use multi-sequence pfetch server via a direct TCP connection:
my $pfetch_server = $PFETCH_SERVER_LIST->[0][0];
my $pfetch_port   = $PFETCH_SERVER_LIST->[0][1];

sub new {
    my $pkg         = shift @_;
    my $slice       = shift @_;
    my $transcript  = shift @_ || 0;
    my $chains      = shift @_ || [];

    my $self = bless {}, $pkg;

    $self->slice($slice);
    $self->chains($chains);
    $self->transcript($transcript);

    return $self;
}

sub slice {
    my $self = shift @_;

    if(@_) {
        $self->{_slice} = shift @_;
    }
    return $self->{_slice};
}

sub transcript {
    my $self = shift @_;

    if(@_) {
        $self->{_transcript} = shift @_;
    }
    return $self->{_transcript};
}

sub chains {
    my $self = shift @_;

    if(@_) {
        $self->{_chains} = shift @_;
    }
    return $self->{_chains};
}

sub emit_sliceseq_to_file {
    my $self    = shift @_;
    my $outfile = shift @_;
    my $seqname = shift @_ || $self->slice()->name();
                                                                                                     
    my $seqobj = Bio::Seq->new(
        -display_id => $seqname,
        -seq => $self->slice()->seq(),
    );
    my $out = Bio::SeqIO->new(-file => ">$outfile" , '-format' => 'Fasta');
    $out->write_seq($seqobj);
}

sub parse_cigar_along_hit { # not a method
    my $cigar  = shift @_;
    my $strand = shift @_;

    my @deque = ();

    while($cigar=~/(\d*)([MID])/g) {
        my $len = $1 || 1;
        my $cmd = $2;
        my $pair = join(':', $cmd, $len);

        if($strand == 1) {
            push @deque, $pair;
        } else {
            unshift @deque, $pair;
        }
    }
    return \@deque;
}

sub Evi::EviChain::to_blixem_strings {
    use strict;

    my $chain  = shift @_;

    my $unit = $chain->unit();
    my @lines = ();

    my $strand = $chain->strand()*$chain->hstrand();
    my $prefixed_name = $chain->prefixed_name;
    for my $af (@{$chain->afs_lp()}) {
        my ($start, $end, $hstart, $hend) =
            ($af->start(), $af->end(), $af->hstart(), $af->hend());

        my $frame = $start*$strand % 3 || 3; # this is how BLIXEM wants it to be

        my @syll = (
            int($af->percent_id()), # $af->score(),
            ($strand == 1)
                ? ( "(+$frame)", $start, $end)
                : ( "(-$frame)", $end, $start),
            $hstart,
            $hend,
            $prefixed_name
        );

        my $hcurr = $hstart;
        my $qcurr = ($strand == 1) ? $start : $end;

        for my $pair (@{ parse_cigar_along_hit($af->cigar_string(), $chain->hstrand()) }) {
            my ($cmd, $len) = split(':', $pair);

                # NB: cigar's units are always query-sequence's units.
            if($cmd eq 'D') {
                $hcurr += $len/$unit;
                next;
            } elsif($cmd eq 'I') {
                $qcurr += $len*$strand;
                next;
            } else { # $cmd eq 'M'
                my $hnext = $hcurr + ($len/$unit - 1);
                my $qnext = $qcurr + ($len - 1)*$strand;
                
                push @syll, join(' ', $hcurr, $hnext, $qcurr, $qnext);

                $hcurr = $hnext + 1;
                $qcurr = $qnext + $strand;
            }
        }
        push @lines, join("\t", @syll)."\n";
    }
    return @lines;
}

sub Bio::EnsEMBL::Transcript::get_all_split_Exons { # based on the original code of get_all_translateable_Exons
    use strict;

    my $transcript  = shift @_;
    my $translation = $transcript->translation();
    my $start_exon  = $translation ? $translation->start_Exon : 0;
    my $end_exon    = $translation ? $translation->end_Exon : 0;

    my @origex      = @{ $transcript->get_all_Exons() }; # caching against destruction
    my @splitex     = ();
    my $currtype    = $translation ? '5UTR' : 'UTR';

    foreach my $exon_ind (1..@origex) {
        my $exon = $origex[$exon_ind-1];

        if ($exon == $start_exon) { # end of 5'UTR
            my $utr5 = $exon->adjust_start_end(0, $translation->start()-1-$exon->length());
            $utr5->{_bltype} = '5UTR';
            $utr5->{_blnum}  = $exon_ind;
            push @splitex, $utr5;

            $currtype = 'CDS'; # start of CDS
            $exon = $exon->adjust_start_end($translation->start()-1,0);
        }
        
        if ($exon == $end_exon) { # end of CDS
            my $cds = $exon->adjust_start_end(0, $translation->end()-$exon->length());
            $cds->{_bltype} = 'CDS';
            $cds->{_blnum}  = $exon_ind;
            push @splitex, $cds;

            $currtype = '3UTR'; # start of 3'UTR
            $exon = $exon->adjust_start_end($translation->end(),0);
        }

        if($exon->length()) { # if there is something left,
            $exon->{_bltype} = $currtype;
            $exon->{_blnum}  = $exon_ind;
            push @splitex, $exon;
        }
    }
    return \@splitex;
}

sub Bio::EnsEMBL::Transcript::to_blixem_strings {
    use strict;

    my $transcript = shift @_;
    my $unit       = shift @_;

    my @lines = ();
    my $len_so_far = 0;

    for my $exon ( @{ $transcript->get_all_split_Exons() }) {

        my ($start, $end, $exonlen, $strand) = ($exon->start(), $exon->end(), $exon->length(), $exon->strand());
        my ($hstart, $hend) = ( $len_so_far+1, $len_so_far+$exonlen );

        my $name = 'Exon'.$exon->{_blnum}.'_'.$exon->{_bltype};
        my $phase = $exon->phase();
        my $frame = ( ($strand==1)
                     ? ($exon->start() - $phase)
                     : -($exon->end() + 1 + $phase)
                    ) % $unit || $unit;

        push @lines, join("\t",
            -1, # signifies an exon
            ($strand == 1)
                ? ( "(+$frame)", $start, $end)
                : ( "(-$frame)", $end, $start),
            $hstart,
            $hend,
            $name,
        )."\n";

        $len_so_far += $exonlen;
    }

    for my $intron (@{ $transcript->get_all_Introns() }) {
        push @lines, join("\t",
            -2, # signifies an intron
            ($intron->strand() == 1)
                ? ( '(+1)', $intron->start(), $intron->end() )
                : ( '(-1)', $intron->end(), $intron->start() ),
            0,
            0,
            'Intron' # nobody sees these names anyway
        )."\n";
    }

    return @lines;
}

sub emit_trans_chains_to_file {
    my $self        = shift @_;
    my $outfile     = shift @_;
    my $unit        = shift @_ || 1;

    my $blasttype = { 1 => 'blastN', 3 => 'blastX'}->{$unit};

    my $transcript = $self->transcript();
    my $chains     = $self->chains();

    open(OUT,">$outfile");
    print OUT "# exblx\n";
    print OUT "# $blasttype\n";
    if($transcript) {
        print OUT $transcript->to_blixem_strings($unit);
    }
    for my $chain (@$chains) {
        if($unit == $chain->unit()) { # only show the chains intended for current display
            print OUT $chain->to_blixem_strings();
        }
    }
    close OUT;
}

sub launch {
    my $self        = shift @_;
    my $unit        = shift @_;

    my $pid           = $$;  # child's PID, which is unique
    my $slice_file    = $tmp_dir."/blixem_slice.$pid";
    my $chains_file   = $tmp_dir."/blixem_chains.$pid";

    $self->emit_sliceseq_to_file($slice_file);
    $self->emit_trans_chains_to_file($chains_file, $unit);

    exec('blixem',
            $quick_pfetch
                ? ('-P', join(':', $pfetch_server, $pfetch_port) )  # use multiseq pfetch server
                : (),                                               # pfetch them 1-by-1
            $remove_files
                ? ('-r')
                : (), # remove the files after using them (which actually happens at startup!)
            $slice_file, $chains_file);
}

sub forklaunch {
    my $self        = shift @_;
    my $unit        = shift @_;

    $SIG{CHLD} = 'IGNORE'; # we do not want to wait for the children

    if (my $pid = fork) { # nonzero => the parent simply returns
        return;
    } elsif (defined $pid) { # zero => the child executes the function AND TERMINATES
        $self->launch($unit);
        exit(0);
    } else {
        warn "Unable to fork : $!";
    }
}

1;

