package Bio::Vega::Exon;

use strict;
use base 'Bio::EnsEMBL::Exon';

sub vega_hashkey_structure {
    return 'seq_region_name-seq_region_start-seq_region_end-seq_region_strand-phase-end_phase';
}

sub vega_hashkey {
    my $self = shift;
    
    return join('-',
        $self->seq_region_name,
        $self->seq_region_start,
        $self->seq_region_end,
        $self->seq_regin_strand,
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

1;

