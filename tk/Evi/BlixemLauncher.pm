package Evi::BlixemLauncher;

# Just launch Blixem with the slice and a set of EviChains
#
# NB: works only on EST/mRNA chains, may fail on protein chains
#
# lg4

use Hum::Conf qw{ PFETCH_SERVER_LIST }; # to get the default pfetch server and port

use Bio::Seq;               # for emitting the fasta sequence of the slice
use Bio::SeqIO;

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
    my $chain  = shift @_;

    my @lines = ();

    my $strand = $chain->hstrand();
    my $prefixed_name = $chain->prefixed_name;
    for my $af (@{$chain->afs_lp()}) {
        my ($start, $end, $hstart, $hend) =
            ($af->start(), $af->end(), $af->hstart(), $af->hend());
        my $frame = $start % 3 || 3;

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

        for my $pair (@{ parse_cigar_along_hit($af->cigar_string(), $strand) }) {
            my ($cmd, $len) = split(':', $pair);

            if($cmd eq 'D') {
                $hcurr += $len;
                next;
            } elsif($cmd eq 'I') {
                $qcurr += $len*$strand;
                next;
            } else { # $cmd eq 'M'
                my $hnext = $hcurr + ($len - 1);
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

sub Bio::EnsEMBL::Transcript::to_blixem_strings {
    my $transcript = shift @_;

    my @lines = ();

    my @exons = @{ $transcript->get_all_Exons() };
    my $strand = $exons[0]->strand();

    my $len_so_far = 0;

    for my $exon_ind (0..scalar(@exons)-1) {
        my $exon = $exons[$exon_ind];

        my ($start, $end, $exonlen) = ($exon->start(), $exon->end(), $exon->length());
        my ($hstart, $hend) = ( $len_so_far+1, $len_so_far+$exonlen );

        # my $name = $transcript->transcript_info->name();
        my $frame = $start % 3 || 3;

        push @lines, join("\t",
            -1, # signifies an exon
            ($strand == 1)
                ? ( "(+$frame)", $start, $end)
                : ( "(-$frame)", $end, $start),
            $hstart,
            $hend,
            'Exon_'.($exon_ind+1)
        )."\n";

        if($exon_ind < scalar(@exons)-1) { # not the last one

            push @lines, join("\t",
                -2, # signifies an intron
                ($strand == 1)
                    ? ( '(+1)', $end+1, $exons[$exon_ind+1]->start()-1 )
                    : ( '(-1)', $start-1, $exons[$exon_ind+1]->end()+1 ),
                0,
                0,
                'Intron_'.($exon_ind+1)
            )."\n";
        }

        $len_so_far += $exonlen;

    }
    return @lines;
}

sub emit_trans_chains_to_file {
    my $self       = shift @_;
    my $outfile    = shift @_;

    my $transcript = $self->transcript();
    my $chains     = $self->chains();

    open(OUT,">$outfile");
    print OUT "# exblx\n";
    print OUT "# blastN\n";
    if($transcript) {
        print OUT $transcript->to_blixem_strings();
    }
    for my $chain (@$chains) {
        print OUT $chain->to_blixem_strings();
    }
    close OUT;
}

sub launch {
    my $self        = shift @_;

    my $tmp_dir       = '.'; # '/tmp'; # (-w '/tmp') ? '/tmp' : (-w '.') ? '.' : $ENV{HOME};
    my $pid           = $$;  # child's PID, which is unique
    my $slice_file    = $tmp_dir."/blixem_slice.$pid";
    my $chains_file   = $tmp_dir."/blixem_chains.$pid";
    my $pfetch_server = $PFETCH_SERVER_LIST->[0][0];
    my $pfetch_port   = $PFETCH_SERVER_LIST->[0][1];
    my $quick_pfetch  = 1;

    $self->emit_sliceseq_to_file($slice_file);
    $self->emit_trans_chains_to_file($chains_file);

    exec('blixem', $quick_pfetch
                ? ('-P', join(':', $pfetch_server, $pfetch_port) )  # use multiseq pfetch server
                : (),                                               # pfetch them 1-by-1
            '-r', # remove the files after using them (which actually happens at startup!)
            $slice_file, $chains_file);
}

sub forklaunch {
    my $self        = shift @_;

    $SIG{CHLD} = 'IGNORE'; # we do not want to wait for the children

    if (my $pid = fork) { # nonzero => the parent simply returns
        return;
    } elsif (defined $pid) { # zero => the child executes the function AND TERMINATES
        $self->launch();
        exit(0);
    } else {
        warn "Unable to fork : $!";
    }
}

1;

