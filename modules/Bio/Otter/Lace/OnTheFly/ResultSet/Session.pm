package Bio::Otter::Lace::OnTheFly::ResultSet::Session;

# The old production version, for use in SessionWindow->launch_exonerate().

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::ResultSet';
with    'Bio::Otter::Lace::OnTheFly::Format::Ace';
with    'Bio::Otter::Lace::OnTheFly::Format::GFF';

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
