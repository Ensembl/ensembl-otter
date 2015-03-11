package Bio::Vega::Tiler;

use strict;
use warnings;

use Bio::EnsEMBL::FeaturePair;

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

sub tile_features {
    my ($self, $coord_system_name) = @_;
    $coord_system_name //= 'seqlevel';

    my $slice = $self->slice;

    my @features;
    foreach my $tile (@{ $slice->project($coord_system_name) }) {
        my $tile_slice = $tile->to_Slice;
        my $sf = Bio::EnsEMBL::FeaturePair->new(
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
        push @features, $sf;
    }
    return @features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

