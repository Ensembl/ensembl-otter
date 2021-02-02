=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Vega::Exon;

use strict;
use warnings;
use base 'Bio::EnsEMBL::Exon';

sub new_dissociated_copy {
    my ($self) = @_;

    my $pkg = ref($self);
    my $copy = $pkg->new_fast(+{
        map { $_ => $self->{$_} } (
            'created_date',
            'end',
            'end_phase',
            'is_constitutive',
            'is_current',
            'modified_date',
            'phase',
            'slice',
            'stable_id',
            'start',
            'strand',
            'version',
        )
                               });

    return $copy;
}

sub adjust_start_end {
    my ($self, @args) = @_;

    my $ensembl_exon = $self->SUPER::adjust_start_end(@args);

    return bless $ensembl_exon, 'Bio::Vega::Exon'; ## no critic (Anacode::ProhibitRebless)
}

sub vega_hashkey_structure {
    return 'seq_region_name-seq_region_start-seq_region_end-seq_region_strand-phase-end_phase';
}

sub vega_hashkey {
    my ($self) = @_;

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
    my ($self, @args) = @_;

    if(@args) {
        $self->{_last_db_version} = shift @args;
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

    return;
}

1;

__END__

=head1 NAME - Bio::Vega::Exon

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

