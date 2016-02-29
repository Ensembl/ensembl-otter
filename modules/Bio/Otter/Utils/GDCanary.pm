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

    # loggers may already be gone
    if (*STDERR) {
        warn "Global destruction canary gone";
    }
    return;
}

__PACKAGE__->new;

1;
