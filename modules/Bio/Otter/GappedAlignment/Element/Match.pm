=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### Bio::Otter::GappedAlignment::Element::Match

package Bio::Otter::GappedAlignment::Element::Match;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::MatchT';

sub type {
    return 'M';
}

sub long_type {
    return 'match';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Match

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
