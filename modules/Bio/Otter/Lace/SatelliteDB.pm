
### Bio::Otter::Lace::SatelliteDB

package Bio::Otter::Lace::SatelliteDB;

use strict;
use warnings;
use Carp;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

sub get_DBAdaptor {
    my ($otter_db, $key, $class) = @_;

    confess "Missing otter_db argument" unless $otter_db;

    $class ||= 'Bio::EnsEMBL::DBSQL::DBAdaptor';

    my $satellite_options = get_options_for_key($otter_db, $key)
        or return;

    my $satellite_db = $class->new(%$satellite_options)
        or confess "Couldn't connect to satellite db";

    return $satellite_db;
}

sub get_options_for_key {
    my ($db, $key) = @_;
    my ($opt_str) = @{ $db->get_MetaContainer()->list_value_by_key($key) };
    return unless $opt_str;
    my %options = eval $opt_str; ## no critic (BuiltinFunctions::ProhibitStringyEval)
    confess "Error evaluating '$opt_str' : $@" if $@;
    return { map { uc $_ => $options{$_} } keys %options };
}

sub remove_options_hash_for_key{
    my ($db, $key) = @_;
    my $sth = $db->dbc->prepare("DELETE FROM meta where meta_key = ?");
    $sth->execute($key);
    $sth->finish();
    return;
}

sub save_options_hash {
    my ($db, $key, $options_hash) = @_;

    confess "missing key argument"          unless $key;
    confess "missing options hash argument" unless $options_hash;

    my @opt_str;
    foreach my $key (sort keys %$options_hash) {
        my $val = $options_hash->{$key};
        push(@opt_str, sprintf "'%s' => '%s'", lc($key), $val);
    }
    my $sth = $db->dbc->prepare("INSERT INTO meta(meta_key, meta_value) VALUES (?,?)");
    $sth->execute($key, join(", ", @opt_str));    

    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::SatelliteDB

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

