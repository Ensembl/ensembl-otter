package Bio::Otter::ServerAction::XML::Region;

use strict;
use warnings;

use Bio::Vega::Region;
use Bio::Vega::Transform::Otter;
use Bio::Vega::Transform::XML;

use base 'Bio::Otter::ServerAction::Region';

=head1 NAME

Bio::Otter::ServerAction::XML::Region - server requests on a region, serialised via XML

=cut


### Serialisation & Deserialisation methods

sub serialise_region {
    my ($self, $region) = @_;

    warn "Converting slice to XML...\n";
    my $formatter = Bio::Vega::Transform::XML->new;
    $formatter->region($region);
    my $xml = $formatter->generate_OtterXML;
    warn "Done converting slice to XML. Length of XML = " . length($xml) . "\n";

    return $xml;
}

sub deserialise_region {
    my ($self, $xml_string) = @_;

    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parse($xml_string);

    my $region = Bio::Vega::Region->new;
    $region->slice($parser->get_ChromosomeSlice);
    $region->clone_sequences($parser->get_CloneSequences);
    $region->genes(@{$parser->get_Genes});
    $region->seq_features(@{$parser->get_SimpleFeatures});

    return $region;
}

sub deserialise_lock_token {
    my ($self, $token) = @_;

    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parse($token);

    return $parser->get_ChromosomeSlice;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
