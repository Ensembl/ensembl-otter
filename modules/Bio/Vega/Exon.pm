package Bio::Vega::Exon;

use strict;
use base 'Bio::EnsEMBL::Exon';

sub adjust_start_end {
    my $self = shift @_;

    my $ensembl_exon = $self->SUPER::adjust_start_end(@_);

    return bless $ensembl_exon, 'Bio::Vega::Exon';
}

sub vega_hashkey_structure {
    return 'seq_region_name-seq_region_start-seq_region_end-seq_region_strand-phase-end_phase';
}

sub vega_hashkey {
    my $self = shift;
    
    return join('-',
        $self->seq_region_name,
        $self->seq_region_start,
        $self->seq_region_end,
        $self->seq_region_strand,
        $self->phase,
        $self->end_phase,
        );
}

# This is to be used by storing mechanism of GeneAdaptor,
# to simplify the loading during comparison.

sub last_db_version {
    my $self = shift @_;

    if(@_) {
        $self->{_last_db_version} = shift @_;
    }
    return $self->{_last_db_version};
}

sub swap_slice {
    my ($self, $new_slice) = @_;
    
    my $old_slice = $self->slice;
    return if $old_slice == $new_slice;
    
    my $offset = $old_slice->start - $new_slice->start;
    $self->start($self->start + $offset);
    $self->end(  $self->end   + $offset);
    $self->slice($new_slice);
}

1;

