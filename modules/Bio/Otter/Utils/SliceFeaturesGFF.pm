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

package Bio::Otter::Utils::SliceFeaturesGFF;

use strict;
use warnings;

=pod

=head1 NAME - Bio::Otter::Utils::SliceFeaturesGFF

Common method for writing GFF from features fetched from a (local) EnsEMBL-like DB

=cut

use Carp;

use Bio::Otter::Utils::FeatureSort qw( feature_sort );
use Bio::Vega::Enrich::SliceGetSplicedAlignFeatures;
use Bio::Vega::Utils::GFF;
use Bio::Vega::Utils::EnsEMBL2GFF;

sub new {
    my ($class, @args) = @_;
    my $self = { @args };
    croak "must supply dba arg" unless $self->{dba};
    return bless $self, $class;
}

sub slice {
    my ($self, @args) = @_;
    ($self->{'slice'}) = @args if @args;
    my $slice = $self->{'slice'};
    return $slice if $slice;
    return $self->{'slice'} = $self->_build_slice;
}

# In _build_slice and features_from_slice, there is overlap with MappingFetcher & Server::GFF,
# but probably not enough to share code?

sub _build_slice {
    my ($self) = @_;
    my $slice = $self->dba->get_SliceAdaptor()->fetch_by_region(
        $self->cs,
        $self->name,
        $self->start,
        $self->end,
        1,      # somehow strand parameter is needed
        $self->csver,
        );
    croak "Could not fetch slice" unless $slice;
    return $slice;
}

sub features_from_slice {
    my ($self) = @_;

    my $feature_kind = $self->feature_kind;
    my $getter_method = "get_all_${feature_kind}s";

    my @logic_names = $self->logic_name ? split(/,/, $self->logic_name) : ( undef );
    my @features;

    foreach my $logic_name ( @logic_names ) {
        my $feats = $self->slice->$getter_method($logic_name);
        push @features, @$feats;
    }

    return \@features;
}

sub gff_for_features {
    my ($self, $features) = @_;

    my %gff_args = (
        gff_format        => Bio::Vega::Utils::GFF::gff_format($self->gff_version),
        gff_source        => $self->gff_source,
        %{$self->extra_gff_args},
        );

    if ($self->extra_gff_args->{transcript_analyses}) {
        # Let gff_source be set from the analysis gff_source field
        delete $gff_args{gff_source};
    }

    my $gff = Bio::Vega::Utils::GFF::gff_header($self->gff_version);
    foreach my $f (feature_sort @$features) {
        $gff .= $f->to_gff(%gff_args);
    }
    return $gff;
}

sub dba {
    my ($self, @args) = @_;
    ($self->{'dba'}) = @args if @args;
    my $dba = $self->{'dba'};
    return $dba;
}

sub cs {
    my ($self, @args) = @_;
    ($self->{'cs'}) = @args if @args;
    my $cs = $self->{'cs'};
    return $cs;
}

sub csver {
    my ($self, @args) = @_;
    ($self->{'csver'}) = @args if @args;
    my $csver = $self->{'csver'};
    return $csver;
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

sub feature_kind {
    my ($self, @args) = @_;
    ($self->{'feature_kind'}) = @args if @args;
    my $feature_kind = $self->{'feature_kind'};
    return $feature_kind;
}

sub logic_name {
    my ($self, @args) = @_;
    ($self->{'logic_name'}) = @args if @args;
    my $logic_name = $self->{'logic_name'};
    return $logic_name;
}

sub gff_version {
    my ($self, @args) = @_;
    ($self->{'gff_version'}) = @args if @args;
    my $gff_version = $self->{'gff_version'};
    return $gff_version;
}

sub gff_source {
    my ($self, @args) = @_;
    ($self->{'gff_source'}) = @args if @args;
    my $gff_source = $self->{'gff_source'};
    return $gff_source;
}

sub extra_gff_args {
    my ($self, @args) = @_;
    ($self->{'extra_gff_args'}) = @args if @args;
    my $extra_gff_args = $self->{'extra_gff_args'};
    return $extra_gff_args // {};
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

