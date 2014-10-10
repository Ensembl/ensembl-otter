# line 2 B:O:U:GDCanary
package Bio::Otter::Utils::GDCanary;
use strict;
use warnings;

sub new {
    my ($pkg) = @_;
    my $self = {};
    $self->{circular} = $self;
    bless $self, $pkg;
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    warn "Global destruction canary gone"; # loggers may already be gone
}

__PACKAGE__->new;

1;
