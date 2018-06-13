=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
