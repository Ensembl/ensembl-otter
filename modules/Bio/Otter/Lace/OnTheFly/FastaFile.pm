package Bio::Otter::Lace::OnTheFly::FastaFile;

use namespace::autoclean;
use Moose::Role;                # THIS IS A ROLE, not a class

requires 'seqs_for_fasta';
requires 'description_for_fasta';

use File::Temp;
use Hum::FastaFileIO;

has 'fasta_file'   => ( is => 'ro', isa => 'File::Temp',
                        lazy => 1, builder => '_build_fasta_file', init_arg => undef );

sub _build_fasta_file {         ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;

    my $template = sprintf("otf_%s_%d_XXXXX", $self->description_for_fasta, $$);
    my $file = File::Temp->new(
        TEMPLATE => $template,
        TMPDIR   => 1,
        SUFFIX   => '.fa',
        UNLINK   => 0,
        );

    my $ts_out  = Hum::FastaFileIO->new("> $file");
    $ts_out->write_sequences( $self->seqs_for_fasta );
    $ts_out = undef;            # flush

    return $file;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
