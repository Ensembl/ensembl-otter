
package Bio::Otter::Server::GFF::FuncGen;

use strict;
use warnings;

use base qw( Bio::Otter::Server::GFF );

# Inject the necessary get_all_ method into slice
#
sub Bio::EnsEMBL::Slice::get_all_SegmentationFeatures {
    my ($slice, $featureset_name) = @_;

    my $funcgen_dba = $slice->adaptor->efgdb;

    my $featureset_adaptor = $funcgen_dba->get_adaptor('featureset');
    my $featureset = $featureset_adaptor->fetch_by_name($featureset_name);
    die "Cannot get featureset for '$featureset_name'" unless $featureset;

    my $segmentation_feature_adaptor = $funcgen_dba->get_adaptor('segmentationfeature');
    my $seg_features = $segmentation_feature_adaptor->fetch_all_by_Slice_FeatureSets($slice, [ $featureset ]);

    return $seg_features;
}

sub ensembl_adaptor_class {
    my ($self) = @_;
    return 'Bio::EnsEMBL::Funcgen::DBSQL::DBAdaptor';
}

# TODO: make the call_args list sub-classable in Bio::Otter::Server::GFF so that we can do away
#       with reimplementing this - especially if we need to add other feature_kinds.

sub get_requested_features {
    my ($self) = @_;

    my $map = $self->make_map;

    my $feature_kind    = $self->require_argument('feature_kind');
    die "feature_kind '$feature_kind' not supported" unless $feature_kind eq 'SegmentationFeature';

    my $metakey         = $self->require_argument('metakey'); # to find funcgen db
    my $featureset_name = $self->require_argument('featureset');

    return $self->fetch_mapped_features_ensembl('get_all_SegmentationFeatures', [ $featureset_name ], $map, $metakey);
}

1;
