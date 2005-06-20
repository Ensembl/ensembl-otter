package Evi::BlixemLauncher;

# Just launch Blixem with the slice and a set of EviChains
#
# lg4

use Bio::Seq;               # for emitting the fasta sequence of the slice
use Bio::SeqIO;

sub new {
    my $pkg    = shift @_;
    my $slice  = shift @_;
    my $chains = shift @_ || [];

    my $self = bless {}, $pkg;

    $self->slice($slice);
    $self->chains($chains);

    return $self;
}

sub slice {
    my $self = shift @_;

    if(@_) {
        $self->{_slice} = shift @_;
    }
    return $self->{_slice};
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

sub emit_chains_to_file {
    my $self    = shift @_;
    my $outfile = shift @_;
    my $chains  = shift @_;

    open(OUT,">$outfile");
    print OUT "# exblx\n";
    print OUT "# blastN\n";
    for my $chain (@$chains) {
        my $strand = $chain->hstrand();
        my $prefixed_name = $chain->prefixed_name;
        for my $af (@{$chain->afs_lp()}) {
            my ($start, $end, $hstart, $hend) =
                ($af->start(), $af->end(), $af->hstart(), $af->hend());
            my $frame = $start % 3 || 3;
            print OUT join("\t",
                int($af->percent_id()), # $af->score(),
                ($strand == 1)
                    ? ( '(+1)', $start, $end)
                    : ( '(-1)', $end, $start),
                $hstart,
                $hend,
                $prefixed_name,
                '',
            );
            my $cigar = $af->cigar_string();
            print "$prefixed_name: ($start, $end) $cigar\n";

            my $hcurr = $hstart;
            my $qcurr = ($strand == 1) ? $start : $end;

            while($cigar=~/(\d*)([MID])/g) {
                my $len = $1 || 1;
                my $cmd = $2;

                if($cmd eq 'D') {
                    $hcurr += $len;
                    next;
                } elsif($cmd eq 'I') {
                    $qcurr += $len*$strand;
                    next;
                } else { # $cmd eq 'M'
                    my $hnext = $hcurr + ($len - 1);
                    my $qnext = $qcurr + ($len - 1)*$strand;
                    
                    print OUT join(' ', $hcurr, $hnext, $qcurr, $qnext,'');

                    $hcurr = $hnext + 1;
                    $qcurr = $qnext + $strand;
                }
            }
            print OUT "\n";
        }
    }
    close OUT;
}

sub launch {
    my $self   = shift @_;
    my $chains = shift @_ || $self->chains();

    my $tmp_dir = '.'; # '/tmp'; # (-w '/tmp') ? '/tmp' : (-w '.') ? '.' : $ENV{HOME};
    my $slice_file  = $tmp_dir."/blixem_slice.$$";
    my $chains_file = $tmp_dir."/blixem_chains.$$";
    my $rubbish_file = 'myoutput';

    $self->emit_sliceseq_to_file($slice_file);
    $self->emit_chains_to_file($chains_file, $chains);

    system('echo', 'blixem', $slice_file, $chains_file);
    system('blixem', $slice_file, $chains_file);

    unlink($slice_file, $chains_file, $rubbish_file);
}

1;

