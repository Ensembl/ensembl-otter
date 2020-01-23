=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Utils::EnsEMBL

package Bio::Otter::Utils::EnsEMBL;

use strict;
use warnings;

use Readonly;

use Bio::Otter::Utils::StableId;

Readonly my $ENSEMBL_METAKEY => 'ensembl_core_db_head';

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;

    $self->_dataset(@args);
    return $self;
}

sub ensembl_dba {
    my $self = shift;
    return $self->_dataset->satellite_dba($ENSEMBL_METAKEY);
}

sub stable_ids_from_otter_id {
    my ($self, $otter_id) = @_;

    my $external_db = undef;    # all external DBs

    my $dba = $self->ensembl_dba;
    my $object_type = $self->_stable_id_utils->type_for_id($otter_id);
    die "EnsEMBL stable id lookup not supported for exons" if $object_type eq 'Exon';

    my $object_adaptor = $dba->get_adaptor($object_type);
    my $objects = $object_adaptor->fetch_all_by_external_name($otter_id, $external_db);

    my %results_by_name;
    foreach my $object ( @$objects ) {
        ++$results_by_name{$object->stable_id};
    }

    my @stable_ids = keys %results_by_name;

    if (wantarray) {
        return @stable_ids;
    } else {
        warn('More than one stable_id found') if scalar(@stable_ids) > 1;
        return $stable_ids[0];
    }
}

sub _dataset {
    my ($self, @args) = @_;
    if (@args) {
        my ($_dataset) = @args;
        die "dataset must be a Bio::Otter::SpeciesDat::DataSet"
            unless ref $_dataset and $_dataset->isa('Bio::Otter::SpeciesDat::DataSet');
        return $self->{'_dataset'} = $_dataset;
    }
    return $self->{'_dataset'};
}

sub _stable_id_utils {
    my $self = shift;
    my $siu = $self->{'_stable_id_utils'};
    return $siu if $siu;
    return $self->{'_stable_id_utils'} = Bio::Otter::Utils::StableId->new($self->_dataset->otter_dba);
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::EnsEMBL

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

