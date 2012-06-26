package Bio::Otter::Lace::OnTheFly::ResultSet;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use Moose;
use namespace::autoclean;

has type => ( is => 'ro', isa => 'Str', required => 1 );

has raw => (
    traits  => [ 'String' ],
    is      => 'rw',
    isa     => 'Str',
    default => q{},
    handles => {
        add_raw_line => 'append',
    },
    );

has _by_query_id => (
    traits   => [ 'Hash' ],
    isa      => 'HashRef[Bio::Otter::GappedAlignment]',
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        add_by_query_id => 'set',
        by_query_id     => 'get',
        query_ids       => 'keys',
    },
    );

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
