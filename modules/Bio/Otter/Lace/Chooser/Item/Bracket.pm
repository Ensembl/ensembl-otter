=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::Chooser::Item::Bracket

package Bio::Otter::Lace::Chooser::Item::Bracket;

use strict;
use warnings;
use base 'Bio::Otter::Lace::Chooser::Item';

sub is_Bracket {
    return 1;
}

sub string {
    my ($self) = @_;

    return $self->name;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Chooser::Item::Bracket

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

