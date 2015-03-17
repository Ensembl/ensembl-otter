package Bio::Otter::ServerAction::XML::Region;

use strict;
use warnings;

use Bio::Vega::Transform::XMLToRegion;
use Bio::Vega::Transform::RegionToXML;

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

    my $region = Bio::Vega::Transform::XMLToRegion->new->parse($xml_string);
    return $region;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
