package Bio::Otter::Utils::Script::Object;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;

use Moose;

has 'stable_id'     => ( is => 'ro', isa => 'Str' );
has 'name'          => ( is => 'ro', isa => 'Str' );
has 'start'         => ( is => 'ro', isa => 'Int' );
has 'end'           => ( is => 'ro', isa => 'Int' );

# has 'seq_region' => (
#     is       => 'ro',
#     isa      => 'Bio::Otter::Utils::Script::SeqRegion',
#     weak_ref => 1,
#     );

has 'seq_region_name'   => ( is => 'ro', isa => 'Str' );
has 'seq_region_hidden' => ( is => 'ro', isa => 'Bool' );

has 'dataset' => (
    is       => 'ro',
    isa      => 'Bio::Otter::Utils::Script::DataSet',
    weak_ref => 1,
    handles  => [ qw( script ) ],
    );

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
