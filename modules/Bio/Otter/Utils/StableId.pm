=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Utils::StableId

package Bio::Otter::Utils::StableId;

use strict;
use warnings;

use Readonly;

Readonly my %TYPE_MAP => (
    'G' => 'Gene',
    'T' => 'Transcript',
    'P' => 'Translation',
    'E' => 'Exon',
    );

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;

    $self->_dba(@args);
    return $self;
}

sub primary_prefix {
    my $self = shift;
    my $mc = $self->_vega_metacontainer;
    unless ($mc) {
        return 'ENS' if $self->_metacontainer; # we have a metacontainer and it's not a vega one.
        return;                                # no metacontainer.
    }
    return $mc->get_primary_prefix;
}

sub species_prefix {
    my $self = shift;
    my $mc = $self->_vega_metacontainer;
    return unless $mc;
    return $mc->get_species_prefix;
}

sub type_pattern {
    my $self = shift;

    my $type_pattern = $self->{_type_pattern};
    return $type_pattern if $type_pattern;

    my $prefix_primary = $self->primary_prefix || '\w{3}';
    my $prefix_species = $self->species_prefix || '\w{0,6}'; # this seems generous for otter
    $type_pattern = qr(^${prefix_primary}${prefix_species}([TPGE])\d+)i;

    return $self->{_type_pattern} = $type_pattern;
}

sub type_for_id {
    my ($self, $stable_id) = @_;

    my ($typeletter) = uc($stable_id) =~ $self->type_pattern;
    return unless $typeletter;

    return $TYPE_MAP{$typeletter};
}

sub _vega_metacontainer {
    my $self = shift;
    my $mc = $self->_metacontainer;
    return unless $mc and $mc->isa('Bio::Vega::DBSQL::MetaContainer');
    return $mc;
}

sub _metacontainer {
    my $self = shift;
    my $mc = $self->{_metacontainer};
    return $mc if $mc;
    return unless $self->_dba;

    $mc = $self->_dba->get_MetaContainer;
    return $self->{_metacontainer} = $mc;
}

sub _dba {
    my ($self, @args) = @_;
    ($self->{'_dba'}) = @args if @args;
    my $_dba = $self->{'_dba'};
    return $_dba;
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::StableId

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

