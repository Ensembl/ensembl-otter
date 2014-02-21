# Build a dummy SessionWindow object

package OtterTest::SessionWindow;

use strict;
use warnings;

use OtterTest::AceDatabase;

sub new {
    my ($pkg) = @_;

    my $self = bless {}, $pkg;
    $self->AceDatabase(OtterTest::AceDatabase->new);

    return $self;
}

sub AceDatabase {
    my ($self, @args) = @_;
    ($self->{'AceDatabase'}) = @args if @args;
    my $AceDatabase = $self->{'AceDatabase'};
    return $AceDatabase;
}

1;
