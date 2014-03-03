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

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
