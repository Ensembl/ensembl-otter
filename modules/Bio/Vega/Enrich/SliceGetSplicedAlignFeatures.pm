### Bio::Vega::Enrich::SliceGetSplicedAlignFeatures

package Bio::Vega::Enrich::SliceGetSplicedAlignFeatures;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(warning);

sub Bio::EnsEMBL::Slice::get_all_DnaSplicedAlignFeatures {
    my ($self, $logic_name, $score, $dbtype, $hcoverage) = @_;

    if(!$self->adaptor()) {
        warning('Cannot get DnaSplicedAlignFeatures without attached adaptor');
        return [];
    }

    my $db;

    if($dbtype) {
        $db = $self->adaptor->db->get_db_adaptor($dbtype);
        if(!$db) {
            warning("Don't have db $dbtype returning empty list\n");
            return [];
        }
    } else {
        $db = $self->adaptor->db;
    }

    my $dafa = $db->get_DnaSplicedAlignFeatureAdaptor();

    if(defined($score) and defined ($hcoverage)){
        warning "cannot specify score and hcoverage. Using score only";
    }
    if(defined($score)){
        return $dafa->fetch_all_by_Slice_and_score($self,$score, $logic_name);
    }
    return $dafa->fetch_all_by_Slice_and_hcoverage($self,$hcoverage, $logic_name);
}

sub Bio::EnsEMBL::Slice::get_all_ProteinSplicedAlignFeatures {
    my ($self, $logic_name, $score, $dbtype, $hcoverage) = @_;

    if(!$self->adaptor()) {
        warning('Cannot get ProteinSplicedAlignFeatures without attached adaptor');
        return [];
    }

    my $db;

    if($dbtype) {
        $db = $self->adaptor->db->get_db_adaptor($dbtype);
        if(!$db) {
            warning("Don't have db $dbtype returning empty list\n");
            return [];
        }
    } else {
        $db = $self->adaptor->db;
    }

    my $dafa = $db->get_ProteinSplicedAlignFeatureAdaptor();

    if(defined($score) and defined ($hcoverage)){
        warning "cannot specify score and hcoverage. Using score only";
    }
    if(defined($score)){
        return $dafa->fetch_all_by_Slice_and_score($self,$score, $logic_name);
    }
    return $dafa->fetch_all_by_Slice_and_hcoverage($self,$hcoverage, $logic_name);
}

1;

__END__

=head1 NAME - Bio::Vega::Enrich::SliceGetSplicedAlignFeatures

=head1 DESCRIPTION

Adds the following enriched C<< get_all_<type>AlignFeatures >> methods to
Bio::EnsEMBL::Slice, which return corresponding features enriched 
with original feature data, including full feature length, from
the hit_description table, if it exists.

=head2 Bio::EnsEMBL::Slice::get_all_DnaDnaAlignFeatures

Calls Bio::EnsEMBL::Slice::get_all_DnaAlignFeatures and then
enriches the results with Bio::Vega::HitFeatures if possible.

=head2 Bio::EnsEMBL::Slice::get_all_DnaPepAlignFeatures

Calls Bio::EnsEMBL::Slice::get_all_ProteinAlignFeatures and then
enriches the results with Bio::Vega::HitFeatures if possible.

=head1 SEE ALSO

L<Bio::Vega::DnaDnaAlignFeature>
L<Bio::Vega::DnaPepAlignFeature>
L<Bio::Vega::HitDescription>

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

# EOF
