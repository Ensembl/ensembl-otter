package Bio::Otter::Lace::OnTheFly::DBStore;

use namespace::autoclean;

# Designed to mix in with Bio::Otter::Lace::OnTheFly::ResultSet
#
use Moose::Role;

with 'MooseX::Log::Log4perl';

requires 'analysis_name';
requires 'hit_by_query_id';
requires 'hit_query_ids';
requires 'is_protein';

use Bio::EnsEMBL::Analysis;
use Bio::Vega::SplicedAlignFeature::DNA;
use Bio::Vega::SplicedAlignFeature::Protein;

sub db_store {
    my ($self, $slice) = @_;

    return unless ($self->hit_query_ids);

    my $vega_dba = $slice->adaptor->db;

    my ($saf_adaptor, $saf_class);

    if ($self->is_protein) {
        $saf_adaptor = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;
        $saf_class   = 'Bio::Vega::SplicedAlignFeature::Protein';
    } else {
        $saf_adaptor = $vega_dba->get_DnaSplicedAlignFeatureAdaptor;
        $saf_class   = 'Bio::Vega::SplicedAlignFeature::DNA';
    }

    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $self->analysis_name );

    my $count = 0;

    foreach my $hname ($self->hit_query_ids) {

        foreach my $ga (@{ $self->hit_by_query_id($hname) }) {

            my %feature_args = (
                '-vulgar'     => $ga,
                '-analysis'   => $analysis,
                '-percent_id' => $ga->percent_id,
                '-slice'      => $slice,
                );

            my $saf = $saf_class->new( %feature_args );
            $saf_adaptor->store($saf);
            ++$count;

        }

    }

    return $count;
}

# Doesn't really belong here - currently only used in t/OtterLaceOTFDBStore.t
#
use Bio::Vega::Utils::EnsEMBL2GFF; # injection of to_gff() into EnsEMBL objects
use Bio::Vega::Utils::GFF;

sub gff_from_db {
    my ($self, $slice) = @_;

    my $vega_dba = $slice->adaptor->db;

    my $saf_a;
    if ($self->is_protein) {
        $saf_a = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;
    } else {
        $saf_a = $vega_dba->get_DnaSplicedAlignFeatureAdaptor;
    }

    my $logic_name = $self->analysis_name;
    my $features = $saf_a->fetch_all_by_logic_name($logic_name);

    my $gff_version = 2;        # FIXME!! is this correct? (see other uses, from DataSet)

    my %gff_args = (
        gff_format        => Bio::Vega::Utils::GFF::gff_format($gff_version),
#       gff_source        => $self->analysis_name,
        gff_source        => $self->gff_method_tag, # TEMP for testing
        use_ensembl_cigar => 1,
        );

    my $gff = Bio::Vega::Utils::GFF::gff_header($gff_version,
                                                $slice->seq_region_name,
                                                $slice->start,
                                                $slice->end);

    foreach my $saf (@$features) {

        foreach my $af ($saf->as_AlignFeatures) {

            # $af->slice($slice);
            $gff .= $af->to_gff(%gff_args);

        }

    }

    return $gff;
}

# This doesn't belong here either, really? - currently only used in t/OtterLaceOTFDBStore.t
#
sub clear_db {
    my ($self, $slice) = @_;

    my $vega_dba = $slice->adaptor->db;
    my $d_saf_a = $vega_dba->get_DnaSplicedAlignFeatureAdaptor;
    my $p_saf_a = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;

    $d_saf_a->remove_by_Slice($slice);
    $p_saf_a->remove_by_Slice($slice);

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
