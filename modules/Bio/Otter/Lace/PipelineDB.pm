
### Bio::Otter::Lace::PipelineDB

package Bio::Otter::Lace::PipelineDB;

use Bio::Otter::Lace::SatelliteDB;
use strict;
use Carp;


sub get_DBAdaptor {
    my( $otter_db, $rw ) = @_;

    return Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db', 'Bio::Otter::DBSQL::DBAdaptor');
}

sub get_rw_DBAdaptor {
    my( $otter_db ) = @_;
    
    return Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db_rw', 'Bio::Otter::DBSQL::DBAdaptor');
}

sub get_pipeline_DBAdaptor {
    my( $otter_db, $inherit_assembly_type ) = @_;

    require Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
    my $pipe_db = Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db', 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor');

    if($inherit_assembly_type) {
        $pipe_db->assembly_type($otter_db->assembly_type());
    }

    return $pipe_db;
}

sub get_pipeline_rw_DBAdaptor {
    my( $otter_db, $inherit_assembly_type ) = @_;
    
    require Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
    my $pipe_db =  Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $otter_db, 'pipeline_db_rw', 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor');

    if($inherit_assembly_type) {
        $pipe_db->assembly_type($otter_db->assembly_type());
    }

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
B<pipeline_db> in the meta table of the database
given as the argument to either the subroutines a
DBAdaptor is returned.

C<get_DBAdaptor> returns an instance of a
C<Bio::EnsEMBL::DBSQL::DBAdaptor>, whereas
C<get_pipeline_DBAdaptor> returns a
C<Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor>.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

