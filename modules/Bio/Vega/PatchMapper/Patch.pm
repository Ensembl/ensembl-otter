=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Bio::Vega::PatchMapper::Patch;

use strict;
use warnings;

use List::Util qw(min max);
use Scalar::Util qw(weaken);

use Bio::EnsEMBL::SimpleFeature;

=head1 NAME

Bio::Vega::PatchMapper::Patch

=head1 DESCRIPTION

=cut

sub _mapper {
    my ($self, @args) = @_;
    if (@args) {
        ($self->{'_mapper'}) = @args;
        weaken $self->{'_mapper'};
    }
    my $_mapper = $self->{'_mapper'};
    return $_mapper;
}

sub seq_region_id {
    my ($self, @args) = @_;
    ($self->{'seq_region_id'}) = @args if @args;
    my $seq_region_id = $self->{'seq_region_id'};
    return $seq_region_id;
}

sub new {
    my ($class, %attrs) = @_;

    my $self = bless { %attrs }, $class;
    return $self;
}

sub name {
    my ($self, @args) = @_;
    ($self->{'name'}) = @args if @args;
    my $name = $self->{'name'};
    return $name;
}

sub start {
    my ($self, @args) = @_;
    ($self->{'start'}) = @args if @args;
    my $start = $self->{'start'};
    return $start;
}

sub end {
    my ($self, @args) = @_;
    ($self->{'end'}) = @args if @args;
    my $end = $self->{'end'};
    return $end;
}

sub n_cmps {
    my ($self, @args) = @_;
    ($self->{'n_cmps'}) = @args if @args;
    my $n_cmps = $self->{'n_cmps'};
    return $n_cmps;
}

sub chr_start {
    my ($self, @args) = @_;
    ($self->{'chr_start'}) = @args if @args;
    my $chr_start = $self->{'chr_start'};
    return $chr_start;
}

sub chr_end {
    my ($self, @args) = @_;
    ($self->{'chr_end'}) = @args if @args;
    my $chr_end = $self->{'chr_end'};
    return $chr_end;
}

sub n_map_segs {
    my ($self, @args) = @_;
    ($self->{'n_map_segs'}) = @args if @args;
    my $n_map_segs = $self->{'n_map_segs'};
    return $n_map_segs;
}

=head2 coverage_slice

Return a slice on the source chromosome which covers the overlap of
the full extent of the patch and the source chromosome limits set by
start() and end() in the mapper, if any.

=cut

sub coverage_slice {
    my ($self) = @_;
    my $coverage_slice = $self->{'coverage_slice'};
    return $coverage_slice if $coverage_slice;

    my $sr_slice = $self->_mapper->seq_region_slice;
    my $sr_start = $sr_slice->start;

    my $start = max($sr_start,        $self->chr_start);
    my $end   = min($sr_slice->end,   $self->chr_end);

    $coverage_slice = $sr_slice->sub_Slice($start - $sr_start + 1, $end - $sr_start + 1, 1);

    return $self->{'coverage_slice'} = $coverage_slice;
}

=head2 feature_per_contig

Generate one SimpleFeature on the source chromosome per contig covered
by the patch.

Project the coverage_slice into the contig coordinate space and
generate one SimpleFeature per contig, named after the patch, but on
the coverage_slice which is in chromosome coords.

These are returned as a hashref keyed by contig name.

=cut

sub feature_per_contig {
    my ($self) = @_;

    my $patch_name = $self->name;

    my $coverage_slice = $self->coverage_slice;
    my $src_name   = $coverage_slice->name;

    my $contig_projs = $coverage_slice->project('contig');

    my %features;
    foreach my $proj (@$contig_projs) {
        my $contig_slice = $proj->to_Slice;
        my $contig_name  = $contig_slice->seq_region_name;
        if ($features{$contig_name}) {
            warn "Already have a feature for '$contig_name' on '$src_name' from '$patch_name'\n";
            next;
        }

        my $contig_sf = Bio::EnsEMBL::SimpleFeature->new(
            -start         => $proj->from_start,
            -end           => $proj->from_end,
            -strand        => 1,
            -slice         => $coverage_slice,
            -display_label => $patch_name,
            );
        $features{$contig_name} = $contig_sf;
    }
    return \%features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
