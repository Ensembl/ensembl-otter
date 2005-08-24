
### Bio::Otter::Lace::SatelliteDB

package Bio::Otter::Lace::SatelliteDB;

use strict;
use Carp;
use Bio::EnsEMBL::DBSQL::DBAdaptor;


## takes in an otter_db adaptor and optionally a meta_key value.
## uses these to connect to the otter db and return a db handle for the pipeline db
sub get_pipeline_DBAdaptor {
    my( $otter_db, $key ) = @_;

    require 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor';
    return _get_DBAdaptor($otter_db, $key, 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor');
}

sub get_DBAdaptor {
    my( $otter_db, $key ) = @_;

    return _get_DBAdaptor($otter_db, $key, 'Bio::EnsEMBL::DBSQL::DBAdaptor');
}

sub _get_DBAdaptor {
    my( $otter_db, $key, $class ) = @_;

    confess "Missing otter_db argument" unless $otter_db;

    my $pipe_options = get_options_for_key($otter_db, $key) or return;
    my $pipeline_db = $class->new(%$pipe_options);

    if ($pipeline_db) {
        return $pipeline_db;
    } else {
        confess "Couldn't connect to pipeline db";
    } 
}

sub get_options_for_key {
    my( $db, $key ) = @_;
    
    my ($opt_str) = @{ $db->get_MetaContainer()->list_value_by_key($key) };
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

sub remove_options_hash_for_key{
    my ($db, $key) = @_;
    my $sth = $db->prepare("DELETE FROM meta where meta_key = ?");
    $sth->execute($key);
    $sth->finish();
    return;
}

sub save_options_hash {
    my( $db, $key, $options_hash ) = @_;
    
    confess "missing key argument"          unless $key;
    confess "missing options hash argument" unless $options_hash;
    
    my $opt_str = '';
    while (my ($key, $val) = each %$options_hash) {
        $opt_str .= "'$key' => '$val',\n";
    }
    my $sth = $db->prepare("INSERT INTO meta(meta_key, meta_value) VALUES (?,?)");
    $sth->execute($key, $opt_str);    
}

# Here as insurance in case more circular references that
# are not cleaned up are introduced into the Ensembl API
sub disconnect_DBAdaptor {
    my( $dba ) = @_;
    
    $dba->db_handle->disconnect;
    #destroy_hash($dba, {});
}

#sub destroy_hash {
#    my( $hash, $seen ) = @_;
#    
#    $seen->{$hash} = 1;
#    
#    foreach my $key (keys %$hash) {
#        my $val = $hash->{$key};
#        $hash->{$key} = undef;
#        next if $seen->{$val};
#        
#        my $is_hash = 0;
#        eval{
#            if (keys %$val) {
#                $is_hash = 1;
#            }
#        };
#        destroy_hash($val, $seen) if $is_hash;
#    }
#}

1;

__END__

=head1 NAME - Bio::Otter::Lace::SatelliteDB

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

