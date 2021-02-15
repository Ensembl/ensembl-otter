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

package Bio::Otter::ServerAction::XML::Region;

use strict;
use warnings;

use Bio::Vega::Transform::XMLToRegion;
use Bio::Vega::Transform::RegionToXML;
use Bio::Vega::CoordSystemFactory;
use Bio::Otter::ServerAction::LoutreDB;
use XML::Simple;

use base 'Bio::Otter::ServerAction::Region';

=head1 NAME

Bio::Otter::ServerAction::XML::Region - server requests on a region, serialised via XML

=cut


### Serialisation & Deserialisation methods

sub serialise_region {
    my ($self, $region) = @_;

    warn "Converting slice to XML...\n";
    my $formatter = Bio::Vega::Transform::RegionToXML->new;
    $formatter->region($region);
    my $xml = $formatter->generate_OtterXML;
    warn "Done converting slice to XML. Length of XML = " . length($xml) . "\n";

    return $xml;
}

sub deserialise_region {
    my ($self, $xml_string) = @_;

    my $xml_data = XMLin($xml_string);

    my $parser = Bio::Vega::Transform::XMLToRegion->new;

    my $cs_factory = Bio::Vega::CoordSystemFactory->new(dba => $self->server->otter_dba);
    $parser->coord_system_factory($cs_factory);

    my $region = $parser->parse($xml_string);
    return $region;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
