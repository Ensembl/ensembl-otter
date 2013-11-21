package Bio::Otter::ServerAction;

use strict;
use warnings;

sub new {
    my ($pkg, $server) = @_;
    my $self = { _server => $server };
    bless $self, $pkg;
    return $self;
}

sub server {
    my ($self) = @_;
    return $self->{_server};
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
