=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Utils::Script::Transcript;

use namespace::autoclean;

use Moose;

extends 'Bio::Otter::Utils::Script::Object';

has 'transcript_id' => ( is => 'ro', isa => 'Int', required => 1 );

# Sort this out properly later
# has 'gene' => (
#     is       => 'ro',
#     isa      => 'Bio::Otter::Utils::Script::Gene',
#     weak_ref => 1,
#     );

has 'gene_id'        => ( is => 'ro', isa => 'Int' );
has 'gene_stable_id' => ( is => 'ro', isa => 'Maybe[Str]' );
has 'gene_name'      => ( is => 'ro', isa => 'Str' );

around BUILDARGS => sub {
    my ($orig ,$class, %args) = @_;

    $args{stable_id} = delete $args{transcript_stable_id};
    $args{name}      = delete $args{transcript_name};
    $args{start}     = delete $args{transcript_start};
    $args{end}       = delete $args{transcript_end};

    # This is hokey as we need a dataset list of genes
    # if (my $gene_id = delete $args{gene_id}) {
    #     my %gene_spec = (
    #         gene_id   => $gene_id,
    #         stable_id => delete $args{gene_stable_id),
    #         name      => delete $args{gene_name),
    #         );
    #     $args{gene} = Bio::Otter::Utils::Script::Gene->new(%gene_spec);
    # }

    return $class->$orig(%args);
};

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
