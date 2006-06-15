
### Bio::Otter::Lace::SatelliteDB

package Bio::Otter::Lace::SatelliteDB;

use strict;
use Carp;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

sub get_DBAdaptor {

    my ($satellite_db, $satellite_options) = _get_DBAdaptor_and_options( @_ );

    return $satellite_db;
}

sub _get_DBAdaptor_and_options {
    my( $otter_db, $key, $class ) = @_;

    confess "Missing otter_db argument" unless $otter_db;

    $class ||= 'Bio::EnsEMBL::DBSQL::DBAdaptor';

    my $satellite_options = get_options_for_key($otter_db, $key)
        or return;

    my $satellite_db = $class->new(%$satellite_options)
        or confess "Couldn't connect to satellite db";

    return ($satellite_db, $satellite_options);
}

sub get_options_for_key {
    my( $db, $key ) = @_;
    
    my ($opt_str) = @{ $db->get_MetaContainer()->list_value_by_key($key) };
    if ($opt_str) {
        my %options_hash = (eval $opt_str);
        if ($@) {
            die "Error evaluating '$opt_str' : $@";
        }

        my %uppercased_hash = ();
        while( my ($k,$v) = each %options_hash) {
            $uppercased_hash{uc($k)} = $v;
        }

        return \%uppercased_hash;
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

