package Bio::Otter::Utils::GDCanary;
# line 3 B:O:U:GDCanary
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
    return;
}

__PACKAGE__->new;

1;
