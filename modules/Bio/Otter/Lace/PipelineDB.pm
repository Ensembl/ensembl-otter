=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::PipelineDB

package Bio::Otter::Lace::PipelineDB;

use Bio::Otter::Lace::SatelliteDB;
use strict;
use warnings;
use Carp;


sub get_DBAdaptor {
    my ($otter_db) = @_;

    return Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db_head', 'Bio::Vega::DBSQL::DBAdaptor');
}

sub get_rw_DBAdaptor {
    my ($otter_db) = @_;

    return Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db_rw_head', 'Bio::Vega::DBSQL::DBAdaptor');
}

sub get_pipeline_DBAdaptor {
    my ($otter_db) = @_;

    require Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor;
    my $pipe_db = Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db_head', 'Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor');

    return $pipe_db;
}

sub get_pipeline_rw_DBAdaptor {
    my ($otter_db) = @_;

    require Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor;
    my $pipe_db =  Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db_rw_head', 'Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor');

    return $pipe_db;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::PipelineDB

=head1 SYNOPSIS

  my $dba     = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($otter_dba);
  my $pipedba = Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($otter_dba);

=head1 DESCRIPTION

Using the options hash value stored under the key
B<pipeline_db_head> in the meta table of the database
given as the argument to either the subroutines a
DBAdaptor is returned.

C<get_DBAdaptor> returns an instance of a
C<Bio::EnsEMBL::DBSQL::DBAdaptor>, whereas
C<get_pipeline_DBAdaptor> returns a
C<Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor>.

=head2 Pipeline read-only vs. read-write

Read-only handles may come from the slave database instance, to
improve responsiveness during heavy writes.

=head2 Usage pattern

These subroutines are normally called in "client-side" mode, after
obtaining a L<Bio::Otter::Lace::DataSet>.

It is now (v63+) possible to do this with
L<Bio::Otter::Lace::DataSet/get_pipeline_DBAdaptor> or
L<Bio::Otter::SpeciesDat::DataSet/pipeline_dba>.  Defaults to
read-only.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

