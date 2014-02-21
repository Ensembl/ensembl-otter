# Build a dummy AceDatabase object

package OtterTest::AceDatabase;

use strict;
use warnings;

use OtterTest::Client;

sub new {
    my ($pkg) = @_;

    my $self = bless {}, $pkg;
    $self->Client(OtterTest::Client->new);

    return $self;
}

sub Client {
    my ($self, @args) = @_;
    ($self->{'Client'}) = @args if @args;
    my $Client = $self->{'Client'};
    return $Client;
}

1;
