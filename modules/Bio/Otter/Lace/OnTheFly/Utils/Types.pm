=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Lace::OnTheFly::Utils::Types;

use namespace::autoclean;
use Moose::Util::TypeConstraints;

use Bio::Otter::Lace::OnTheFly::Utils::SeqList;

subtype 'ArrayRefOfHumSeqs'
    => as 'ArrayRef[Hum::Sequence]';

class_type 'SeqListClass'
    => { class => 'Bio::Otter::Lace::OnTheFly::Utils::SeqList' };

coerce 'SeqListClass'
    => from 'ArrayRefOfHumSeqs'
    => via { Bio::Otter::Lace::OnTheFly::Utils::SeqList->new( seqs => $_ ) };

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
