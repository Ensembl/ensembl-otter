# Build a dummy SessionWindow object

package OtterTest::SessionWindow;

use strict;
use warnings;

use OtterTest::AceDatabase;

sub new_mock {
    my ($pkg) = @_;

    my $self = bless {}, $pkg;
    $self->AceDatabase(OtterTest::AceDatabase->new_mock);

    return $self;
}

sub AceDatabase {
    my ($self, @args) = @_;
    ($self->{'AceDatabase'}) = @args if @args;
    my $AceDatabase = $self->{'AceDatabase'};
    return $AceDatabase;
}

sub logger {
    my ($self, $category) = @_;
    return $self->AceDatabase->logger($category);
}

1;
