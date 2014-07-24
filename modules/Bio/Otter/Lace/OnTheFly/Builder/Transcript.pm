package Bio::Otter::Lace::OnTheFly::Builder::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Builder';

has vega_transcript => ( is => 'ro', isa => 'Bio::Vega::Transcript', required => 1 );

augment '_build_default_options'    => sub { return { } };
augment '_build_default_qt_options' => sub {
    return {
        protein => { '--model' => 'protein2dna',  '--refine' => 'region' },
        dna     => { '--model' => 'affine:local', '--refine' => 'region' },
    };
};

sub _build_analysis_prefix { return 'OTF_TS_' }

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
