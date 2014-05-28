package Bio::Otter::Lace::OnTheFly::ResultSet::Test;

# The test version, with all result formats

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::ResultSet';
with    'Bio::Otter::Lace::OnTheFly::Format::Ace';
with    'Bio::Otter::Lace::OnTheFly::Format::DBStore';
with    'Bio::Otter::Lace::OnTheFly::Format::GFF';

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
