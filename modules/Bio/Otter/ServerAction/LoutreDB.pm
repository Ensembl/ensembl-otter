=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Bio::Otter::ServerAction::LoutreDB;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction';

=head1 NAME

Bio::Otter::ServerAction::LoutreDB - serve requests for info from loutre db.

=cut

# Parent constructor is fine unaugmented.

### Methods

=head2 get_meta
=cut

my $select_meta_sql = <<'SQL'
    SELECT species_id, meta_key, meta_value
      FROM meta
  ORDER BY meta_id
SQL
    ;

my @white_list = qw(
    assembly
    patch
    prefix
    schema_type
    schema_version
    species
);

my %white_list = map { $_ => 1 } @white_list;

sub get_meta {
    my ($self) = @_;
    my $server = $self->server;

    my $key_pattern;
    if (my $key_param = $server->param('key')) {
        $key_pattern = qr/^${key_param}/;
    }

    my $sth = $server->otter_dba()->dbc()->prepare($select_meta_sql);
    $sth->execute;

    my $counter = 0;
    my %meta_hash;

    while (my ($species_id, $meta_key, $meta_value) = $sth->fetchrow) {

        my ($key_prefix) = $meta_key =~ /^(\w+)\.?/;
        next unless $white_list{$key_prefix};

        if ($key_pattern) {
            next unless $meta_key =~ $key_pattern;
        }

        $meta_hash{$meta_key}->{species_id} = $species_id;
        push @{$meta_hash{$meta_key}->{values}}, $meta_value; # as there can be multiple values for one key
        $counter++;
    }

    warn "Total of $counter meta table pairs whitelisted\n";

    return \%meta_hash;
}


=head2 get_db_info
=cut

my $select_cs_sql = <<'SQL';
    SELECT coord_system_id, species_id, name, version, rank, attrib
      FROM coord_system
     WHERE name = 'chromosome' AND version = 'Otter'
SQL

my $select_at_sql = <<'SQL';
    SELECT attrib_type_id, code, name, description
      FROM attrib_type
SQL

sub get_db_info {
    my ($self, $coord_system_name, $coord_system_version) = @_;

    my (%results, $select_cs_sql);

    if ($coord_system_name and $coord_system_version) {
        $select_cs_sql = 'SELECT coord_system_id, species_id, name, version, rank, attrib'.
        ' FROM coord_system'.
        " WHERE name = '$coord_system_name' AND version = '$coord_system_version'";
    }
    else {
         $select_cs_sql = 'SELECT coord_system_id, species_id, name, version, rank, attrib'.
        ' FROM coord_system'.
        " WHERE attrib = 'default_version' AND rank = 1";
    }

    my $dbc = $self->server->otter_dba()->dbc();

    my $cs_sth = $dbc->prepare($select_cs_sql);
    $cs_sth->execute;
    my $cs_chromosome = $cs_sth->fetchrow_hashref;
    $results{'coord_system.chromosome'} = $cs_chromosome;

    if (!$coord_system_name and !$coord_system_version) {
        $coord_system_version = $cs_chromosome->{'version'};
        $coord_system_name = $cs_chromosome->{'name'};
    }

    foreach my $coord_system (@{$self->server->otter_dba->get_CoordSystemAdaptor->fetch_all_by_version($coord_system_version)}) {
        $results{'coord_systems'}->{$coord_system->name} = {
        '-version' => $coord_system_version,
        '-rank' => $coord_system->rank,
        '-default' => $coord_system->is_default,
        '-sequence_level' => $coord_system->is_sequence_level
        };
    }
    if ($coord_system_name ne 'primary_assembly' and !exists $results{'coord_systems'}->{contig}) {
        my $contig_cs = $self->server->otter_dba->get_CoordSystemAdaptor->fetch_by_name('contig');
        $results{'coord_systems'}->{contig} = {
        '-rank' => $contig_cs->rank,
        '-default' => $contig_cs->is_default,
        '-sequence_level' => $contig_cs->is_sequence_level
        };
    }
    if ($coord_system_name ne 'primary_assembly' and !exists $results{'coord_systems'}->{clone}) {
        my $clone_cs = $self->server->otter_dba->get_CoordSystemAdaptor->fetch_by_name('clone');
        $results{'coord_systems'}->{clone} = {
        '-rank' => $clone_cs->rank,
        '-default' => $clone_cs->is_default,
        '-sequence_level' => $clone_cs->is_sequence_level
        };
    }
    my $at_sth = $dbc->prepare($select_at_sql);
    $at_sth->execute;
    my $at_rows = $at_sth->fetchall_arrayref({});
    $results{'attrib_type'} = $at_rows;

    my $ed_sth = $dbc->prepare('SELECT * FROM external_db WHERE db_name IN ("INSDC")');
    $ed_sth->execute;
    my $ed_rows = $ed_sth->fetchall_arrayref({});
    $results{'external_db'} = $ed_rows;

    return \%results;
}

### Accessors

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
