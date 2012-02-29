
### Bio::Vega::Utils::XML

package Bio::Vega::Utils::XML;

use strict;
use warnings;

use Bio::Vega::Transform::Otter;
use Bio::Vega::Transform::XML;

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
    my $xml = Bio::Vega::Transform::XML->new->generate_OtterXML(
        $slice,
        $gene->adaptor->db,
        1,
        [$gene],
        [],
        );
    # warn $xml;
    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parse($xml);
    my $xml_gene_list = $parser->get_Genes;
    unless (@$xml_gene_list == 1) {
        die sprintf "Weird.  Put 1 gene into XML but got %d out", scalar @$xml_gene_list;
    }

    my $xml_gene = $xml_gene_list->[0];
    $xml_gene->attach_slice($slice);
    return $xml_gene;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::XML

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

