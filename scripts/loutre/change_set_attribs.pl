#!/usr/bin/env perl

=head1 NAME

change_set_attribs.pl

=head1 SYNOPSIS

change_set_attribs.pl

=head1 DESCRIPTION

This script is used to change the visibility and writability of a sequence set in
any loutre database.

here is an example commandline

./change_set_attribs.pl
-host otterlive
-port 3324
-dbname loutre_human
-user pipuser
-pass *****
-visible
-read

=head1 OPTIONS

    -host (default:otterlive)   host name of the database with missing contig dna
    -dbname (no default)  For RDBs, what database to connect to
    -user (check the ~/.netrc file)  For RDBs, what username to connect as
    -pass (check the ~/.netrc file)  For RDBs, what password to use
    -port (check the ~/.netrc file)   For RDBs, what port to use

    -[write|read]   make the set writable or read-only
    -[visible|hide] make the set visible or hide it
    -set            comma separated list of sequence sets
    -help|h         displays this documentation with PERLDOC

=head1 SQL

  UPDATE seq_region_attrib
  SET value = '0'
  WHERE attrib_type_id = 128
    AND seq_region_id IN
  (SELECT seq_region_id
      FROM seq_region
      WHERE name like '%_20101111')


=head1 SEE ALSO

F<scripts/loutre/sync_set_attributes_and_coord_systems>

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Net::Netrc;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

{

    my $user;
    my $pass;
    my $port;
    my $host = 'otterlive';
    my $dbname;
    my $set;
    my $write;
    my $read;
    my $visible;
    my $hide;

    my $usage = sub { exec('perldoc', $0); };

    GetOptions(
        'host=s'   => \$host,
        'port=n'   => \$port,
        'dbname=s' => \$dbname,
        'user=s'   => \$user,
        'pass=s'   => \$pass,
        'write!'   => \$write,
        'read!'    => \$read,
        'visible!' => \$visible,
        'hide!'    => \$hide,
        'set=s'    => \$set,
        'h|help!'  => $usage
    ) or $usage->();

    if (!$dbname) {
        throw("Need a target pipeline database name (dbname = ?)");
    }

    my @sets = split /,/, $set;

    throw("Must provide a list of set names") unless @sets;

    if ($write && $read) {
        throw("Make the set either writable or read-only, not both !");
    }
    if ($visible && $hide) {
        throw("Make the set either visible or hidden, not both !");
    }

    my $sql = qq{
        UPDATE attrib_type t
          , seq_region s
          , seq_region_attrib a
        SET a.value = ?
        WHERE s.name = ?
          AND s.seq_region_id = a.seq_region_id
          AND t.code = ?
          AND t.attrib_type_id = a.attrib_type_id
    };

    # Reading the DB connexion parameters from ~/.netrc
    my $ref = Net::Netrc->lookup($host);
    if (!$ref) {
        print STDERR "No entry found in ~/.netrc for host $host\n";
        next;
    }
    $user = $ref->login;
    $pass = $ref->password;
    $port = $ref->account;

    # Creating the DB connection
    my $dsn = "DBI:mysql:database=$dbname;host=$host;port=$port";
    my $dbh = DBI->connect($dsn, $user, $pass, { 'RaiseError' => 1 });
    my $sth = $dbh->prepare($sql);

    foreach (@sets) {
        my ($r, $w, $v, $h);

        # Make the set either read-only or visible
        if ($write) {
            $w = $sth->execute(1, $_, 'write_access');
        }
        elsif ($read) {
            $r = $sth->execute(0, $_, 'write_access');
        }

        # Make the set either visible or hidden
        if ($visible) {
            $v = $sth->execute(0, $_, 'hidden');
        }
        elsif ($hide) {
            $h = $sth->execute(1, $_, 'hidden');
        }

        my $out = "Made $_\t";
        $out .= "Writable [" .  ($w > 0 ? "OK" : "FAILED") . "] " if $write;
        $out .= "Read-Only [" . ($r > 0 ? "OK" : "FAILED") . "] " if $read;
        $out .= "Visible [" .   ($v > 0 ? "OK" : "FAILED") . "] " if $visible;
        $out .= "Hidden [" .    ($h > 0 ? "OK" : "FAILED") . "] " if $hide;

        print $out. "\n";
    }
}
