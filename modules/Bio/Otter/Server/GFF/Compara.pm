=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::Otter::Server::GFF::Compara

=head1 SYNOPSIS


=head1 DESCRIPTION


=cut

package Bio::Otter::Server::GFF::Compara;

use strict;
use warnings;

use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Slice;

use base qw( Bio::Otter::Server::GFF );


sub get_requested_features {
    my ($self) = @_;

    my $map = $self->make_map;
    my $feature_kind    = $self->require_argument('feature_kind');
    die "feature_kind '$feature_kind' not supported" unless $feature_kind eq 'SimpleFeature';

    my $metakey = $self->require_argument('metakey'); # to find compara db
    my $method_link = $self->require_argument('method_link');
    my $assembly_name = $self->param('csver');
    my $cs_name = $self->param('cs');
    my $seq_region_name = $self->param('name');
    my $seq_region_start = $self->param('start');
    my $seq_region_end = $self->param('end');
    my $slice = $self->dataset->pipeline_dba->get_SliceAdaptor->fetch_by_region($cs_name, $seq_region_name, undef, undef, undef, $assembly_name);

    my $compara_dba = $self->dataset->satellite_dba( $metakey, 'Bio::EnsEMBL::Compara::DBSQL::DBAdaptor' );

    my $sth = $compara_dba->dbc->prepare(
      'SELECT ce.dnafrag_start, ce.dnafrag_end, ce.dnafrag_strand, ce.p_value, ce.constrained_element_id'.
      ' FROM constrained_element ce, dnafrag d, method_link_species_set mlss, method_link ml, species_set ss, genome_db gd'.
      ' WHERE gd.assembly = ? AND ml.type = ?'.
      ' AND ce.dnafrag_id = d.dnafrag_id AND ce.method_link_species_set_id = mlss.method_link_species_set_id'.
      ' AND mlss.method_link_id = ml.method_link_id AND mlss.species_set_id = ss.species_set_id'.
      ' AND ss.genome_db_id = gd.genome_db_id AND d.genome_db_id = gd.genome_db_id'.
      ' AND d.name = ? AND ce.dnafrag_start >= ? AND ce.dnafrag_end <= ?'
    );
    warn(join(':', $assembly_name, $method_link, $seq_region_name, $seq_region_start, $seq_region_end));
    $sth->execute($assembly_name, $method_link, $seq_region_name, $seq_region_start, $seq_region_end);
    my @features;
    while(my $row = $sth->fetch) {
      warn(join(':', @$row));
      push(@features, Bio::EnsEMBL::SimpleFeature->new(
        -start => $row->[0],
        -end => $row->[1],
        -strand => $row->[2],
        -slice => $slice,
        -score => $row->[3],
        -display_label => $row->[4],
      ));
    }
    return \@features
}

1;
