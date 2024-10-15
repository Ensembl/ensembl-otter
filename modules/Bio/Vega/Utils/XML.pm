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


### Bio::Vega::Utils::XML

package Bio::Vega::Utils::XML;

use strict;
use warnings;

use Bio::Vega::Transform::XMLToRegion;
use Bio::Vega::Transform::RegionToXML;

use base 'Exporter';
our @EXPORT_OK = qw{ freeze_thaw_gene };

=head2 freeze_thaw_gene

  my $xml_gene = freeze_thaw_gene($gene);

Used to create a gene which is no longer connected to the source database,
which is useful when writing scripts which edit genes.

Takes a gene, transfers it to its feature slice, then converts it into Otter
XML and parses it back. The gene from XML is then attached back to the feature
slice, and returned.

=cut

sub freeze_thaw_gene {
    my ($gene) = @_;

    my $slice = $gene->feature_Slice;
    $gene = $gene->transfer($slice);
    die("Broken before refactoring of Bio::Vega::Transform::RegionToXML on 2013-07-15.") if 1;
    # ...as generate_OtterXML takes no arguments, AND XMLToRegion needs a CoordSystemFactory
    my $xml = Bio::Vega::Transform::RegionToXML->new->generate_OtterXML(
        $slice,
        $gene->adaptor->db,
        1,
        [$gene],
        [],
        );
    # warn $xml;
    my $region = Bio::Vega::Transform::XMLToRegion->new->parse($xml);
    my @xml_gene_list = $region->genes;
    unless (@xml_gene_list == 1) {
        die sprintf "Weird.  Put 1 gene into XML but got %d out", scalar @xml_gene_list;
    }

    my $xml_gene = $xml_gene_list[0];
    $xml_gene->attach_slice($slice);
    return $xml_gene;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::XML

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

