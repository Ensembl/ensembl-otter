package Bio::Otter::Lace::OnTheFly::FastaFile;

use namespace::autoclean;
use Moose::Role;                # THIS IS A ROLE, not a class

requires 'seqs_for_fasta';
requires 'description_for_fasta';

use File::Path;
use File::Spec;
use File::Temp;

use Hum::FastaFileIO;

has 'fasta_file'   => ( is => 'ro', isa => 'File::Temp',
                        lazy => 1, builder => '_build_fasta_file', init_arg => undef );

has 'fasta_dir'    => ( is => 'ro', isa => 'Str',
                        lazy => 1, builder => '_build_fasta_dir',   init_arg => undef );

sub _build_fasta_file {         ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;

    my $template = sprintf("%s/otf_%s_%d_XXXXX", $self->fasta_dir, $self->description_for_fasta, $$);
    my $file = File::Temp->new(
        TEMPLATE => $template,
        SUFFIX   => '.fa',
        UNLINK   => 0,
        );

    my $ts_out  = Hum::FastaFileIO->new("> $file");
    $ts_out->write_sequences( $self->seqs_for_fasta );
    $ts_out = undef;            # flush

    return $file;
}

sub _build_fasta_dir {
    my $self = shift;
    my $tmp  = File::Spec->tmpdir;
    my $user = getpwuid($<);
    my $path = sprintf('%s/otter_otf_%s', $tmp, $user);
    File::Path::make_path($path);
    return $path;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
