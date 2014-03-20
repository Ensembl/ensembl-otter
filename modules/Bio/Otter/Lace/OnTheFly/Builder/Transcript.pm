package Bio::Otter::Lace::OnTheFly::Builder::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Builder';

augment '_build_default_options'    => sub { return { } };
augment '_build_default_qt_options' => sub {
    return {
        protein => { '--model' => 'protein2dna',  '--exhaustive' => undef },
        dna     => { '--model' => 'affine:local', '--exhaustive' => undef },
    };
};

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
