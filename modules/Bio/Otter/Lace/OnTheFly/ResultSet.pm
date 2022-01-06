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

package Bio::Otter::Lace::OnTheFly::ResultSet;

use Moose;
use namespace::autoclean;

use Bio::Otter::Lace::OnTheFly::Utils::SeqList;
use Bio::Otter::Lace::OnTheFly::Utils::Types;

# Constructor must supply these:
#
has analysis_name => ( is => 'ro', isa => 'Str',   required => 1 );
has is_protein    => ( is => 'ro', isa => 'Bool',  required => 1 );

has query_seqs    => (
    is       => 'ro',
    isa      => 'SeqListClass',
    required => 1,
    handles  => {
        query_seq_by_name  => 'seq_by_name',
        query_seqs_by_name => 'seqs_by_name',
    },
    coerce => 1,                # allows initialisation from an arrayref
    );

# Raw results store
#
has raw => (
    traits  => [ 'String' ],
    is      => 'rw',
    isa     => 'Str',
    default => q{},
    handles => {
        add_raw_line => 'append',
    },
    );

# This is the main results structure
#
has _hit_by_query_id => (
    traits   => [ 'Hash' ],
    isa      => 'HashRef[ArrayRef[Bio::Otter::GappedAlignment]]',
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        set_hit_by_query_id  => 'set',
        hit_by_query_id      => 'get',
        hit_query_ids        => 'keys',
    },
    );

# ResultSet on its own is not too useful.
# It needs to be subclassed and extended to mix in one or more of the following:
#
# with 'Bio::Otter::Lace::OnTheFly::Format::Ace';
# with 'Bio::Otter::Lace::OnTheFly::Format::GFF';
# with 'Bio::Otter::Lace::OnTheFly::Format::DBStore';

sub add_hit_by_query_id {
    my ($self, $q_id, $ga) = @_;
    my $hit_by_query_id;
    unless ($hit_by_query_id = $self->hit_by_query_id($q_id)) {
        $hit_by_query_id = $self->set_hit_by_query_id($q_id => []);
    }
    push @$hit_by_query_id, $ga;
    return $ga;
}

sub query_ids_not_hit {
    my ($self) = @_;
    return grep { not $self->hit_by_query_id($_) } keys %{$self->query_seqs_by_name};
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
