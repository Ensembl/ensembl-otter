package Bio::Vega::Tiler;

use strict;
use warnings;

use Bio::EnsEMBL::FeaturePair;
use Bio::EnsEMBL::SimpleFeature;

sub new {
    my ($pkg, $slice) = @_;
    return bless { slice => $slice }, $pkg;
}

sub slice {
    my ($self, @args) = @_;
    ($self->{'slice'}) = @args if @args;
    my $slice = $self->{'slice'};
    return $slice;
}

sub feature_pairs {
    my ($self, @args) = @_;
    return $self->_tile_features(\&_build_feature_pair, @args);
}

sub _build_feature_pair {
    my ($slice, $tile, $tile_slice) = @_;
    return Bio::EnsEMBL::FeaturePair->new(
            -start         => $tile->from_start,
            -end           => $tile->from_end,
            -strand        => 1,
            -slice         => $slice,
            -hseqname      => $tile_slice->seq_region_name,
            -hstart        => $tile_slice->start,
            -hend          => $tile_slice->end,
            -hstrand       => $tile_slice->strand,
            -score         => $tile_slice->seq_region_Slice->length, # abused to pass clone length
        );
}

sub simple_features {
    my ($self, @args) = @_;
    return $self->_tile_features(\&_build_simple_feature, @args);
}

sub _build_simple_feature {
    my ($slice, $tile, $tile_slice) = @_;
    my $label = sprintf('%s-%d-%d-%s',
                        $tile_slice->seq_region_name,
                        $tile_slice->start,
                        $tile_slice->end,
                        $tile_slice->strand > 0 ? 'plus' : 'minus',
        );
    return Bio::EnsEMBL::SimpleFeature->new(
            -start         => $tile->from_start,
            -end           => $tile->from_end,
            -strand        => $tile_slice->strand,
            -slice         => $slice,
            -display_label => $label,
        );
}

sub _tile_features {
    my ($self, $feature_builder, $coord_system_name) = @_;
    $coord_system_name //= 'seqlevel';

    my $slice = $self->slice;

    my @features;
    foreach my $tile (@{ $slice->project($coord_system_name) }) {
        my $tile_slice = $tile->to_Slice;
        push @features, $feature_builder->($slice, $tile, $tile_slice);
    }
    return @features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

