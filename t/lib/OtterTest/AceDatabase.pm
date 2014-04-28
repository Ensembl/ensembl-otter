# Build a dummy AceDatabase object

package OtterTest::AceDatabase;

use strict;
use warnings;

use Bio::Otter::Log::WithContext;

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

sub logger {
    my ($self, $category) = @_;
    $category = scalar caller unless defined $category;
    return Bio::Otter::Log::WithContext->get_logger($category, name => 'OtterTest.AceDatabase');
}

1;
