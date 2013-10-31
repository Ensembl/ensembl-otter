package Bio::Otter::Lace::OnTheFly::DBStore;

use namespace::autoclean;

# Designed to mix in with Bio::Otter::Lace::OnTheFly::ResultSet
#
use Moose::Role;

with 'MooseX::Log::Log4perl';

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

    my $d_saf_a = $vega_dba->get_DnaSplicedAlignFeatureAdaptor;
    my $p_saf_a = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;

    # FIXME: once OTF via Ace has gone, this should be........ $self->analysis_name );
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $self->gff_method_tag );

    my $count = 0;

    foreach my $hname ($self->hit_query_ids) {

        foreach my $ga (@{ $self->hit_by_query_id($hname) }) {

            my %feature_args = (
                '-vulgar'   => $ga,
                '-analysis' => $analysis,
                '-slice'    => $slice,
                );

            if ($ga->query_is_protein) {
                my $psaf = Bio::Vega::SplicedAlignFeature::Protein->new( %feature_args );
                $p_saf_a->store($psaf);
                ++$count;
            } else {
                my $dsaf = Bio::Vega::SplicedAlignFeature::DNA->new( %feature_args );
                $d_saf_a->store($dsaf);
                ++$count;
            }

        }

    }

    return $count;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
