=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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
