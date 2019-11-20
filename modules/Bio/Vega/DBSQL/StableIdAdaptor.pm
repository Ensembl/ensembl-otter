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

package Bio::Vega::DBSQL::StableIdAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Author;

use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';


sub fetch_new_gene_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('gene', 'G');
}

sub fetch_new_transcript_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('transcript', 'T');
}

sub fetch_new_exon_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('exon', 'E');
}

sub fetch_new_translation_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('translation', 'P');
}

sub _fetch_new_by_type {
    my ($self, $type, $type_prefix) = @_;

    my $id     = $type . "_id";
    my $poolid = $type . "_pool_id";
    my $table  = $type . "_stable_id_pool";

    my $sql = "insert into $table () values()";
    my $sth = $self->prepare($sql);
    $sth->execute;
    my $num = $self->last_insert_id($poolid, undef, $table) or throw("Failed to get autoincremented '$poolid'");

    my $meta_container = $self->db->get_MetaContainer;
    my $prefix =
        $meta_container->single_value_by_key('species.stable_id_prefix')
      . $type_prefix;

    # Stable IDs are always 18 characters long
    my $rem = 18 - length($prefix);
    return $prefix . sprintf "\%011d", $num;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

