
### Bio::Otter::Lace::PipelineDB

package Bio::Otter::Lace::PipelineDB;

use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
use strict;
use Carp;

## takes in an otter_db adaptor and optionally a meta_key value.
## uses these to connect to the otter db and return a db handle for the pipeline db
sub get_pipeline_DBAdaptor {
    my( $otter_db ) = @_;

    require 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor';
    return _get_DBAdaptor($otter_db, 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor');
}

sub get_DBAdaptor {
    my( $otter_db ) = @_;

    return _get_DBAdaptor($otter_db, 'Bio::EnsEMBL::DBSQL::DBAdaptor');
}

sub _get_DBAdaptor {
    my( $otter_db, $class ) = @_;

    confess "Missing otter_db argument" unless $otter_db;

    my $pipe_options = get_pipeline_options($otter_db);
    my $pipeline_db = $class->new(%$pipe_options);

    if ($pipeline_db) {
        $pipeline_db->assembly_type($otter_db->get_MetaContainer->get_default_assembly);
        return $pipeline_db
    } else {
        confess "Couldn't connect to pipeline db";
    } 
}

sub get_pipeline_options {
    my( $db ) = @_;
    
    my $sth = $db->prepare("SELECT meta_value FROM meta WHERE meta_key = 'pipeline_db'");
    $sth->execute;
    my ($opt_str) = $sth->fetchrow;
    if ($opt_str) {
        my $options_hash = {eval $opt_str};
        if ($@) {
            die "Error evaluating '$opt_str' : $@";
        }
        return $options_hash
    } else {
        return;
    }
}




1;

__END__

=head1 NAME - Bio::Otter::Lace::PipelineDB

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

