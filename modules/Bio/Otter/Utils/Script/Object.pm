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

package Bio::Otter::Utils::Script::Object;

use namespace::autoclean;

use Moose;

has 'stable_id'     => ( is => 'ro', isa => 'Maybe[Str]' );
has 'name'          => ( is => 'ro', isa => 'Str' );
has 'start'         => ( is => 'ro', isa => 'Int' );
has 'end'           => ( is => 'ro', isa => 'Int' );

# has 'seq_region' => (
#     is       => 'ro',
#     isa      => 'Bio::Otter::Utils::Script::SeqRegion',
#     weak_ref => 1,
#     );

has 'seq_region_name'   => ( is => 'ro', isa => 'Str' );
has 'seq_region_hidden' => ( is => 'ro', isa => 'Bool' );

has 'dataset' => (
    is       => 'ro',
    isa      => 'Bio::Otter::Utils::Script::DataSet',
    weak_ref => 1,
    handles  => [ qw( script ) ],
    );

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
