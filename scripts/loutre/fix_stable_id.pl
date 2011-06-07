#!/usr/bin/env perl

=head1 NAME

fix_stable_id.pl

=head1 SYNOPSIS

fix_stable_id.pl

=head1 DESCRIPTION

This script fix a problem of existing stable_id being reused for new gene/transcript/exon/translation objects.
This problem of duplicated stable_id was a consequence of the stable_id_pool tables not being populated after
the database migration to the new schema 20+ (13 February 2008). Only small species databases were affected (Wallaby, rat,..)

here is an example commandline

./fix_stable_id.pl
-host otterlive
-port 3324
-dbname loutre_wallaby
-user pipuser
-pass *****
-write

=head1 OPTIONS

    -host (default:otterlive)   host name of the database with missing contig dna
    -dbname (no default)  For RDBs, what database to connect to
    -user (check the ~/.netrc file)  For RDBs, what username to connect as
    -pass (check the ~/.netrc file)  For RDBs, what password to use
    -port (check the ~/.netrc file)   For RDBs, what port to use

    -verbose    make the script verbose
    -write      write the changes in the database
    -help|h     displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;
use Sys::Hostname;
use Net::Netrc;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Vega::ContigLockBroker;
use Bio::Otter::Lace::Defaults;
use Getopt::Long;
use HTTP::Date;

my $dbname;
my $host = 'otterlive';
my $port;
my $user;
my $pass;
my $verbose = 0;
my $write   = 0;
my $cl      = Bio::Otter::Lace::Defaults::make_Client();
my $author  = $cl->author;
my $email   = $cl->email;
my $usage   = sub { exec( 'perldoc', $0 ); };
my $DATE = "2008-02-13 12:00:00.0"; # The date of the migration

GetOptions(
			'host=s'      => \$host,
			'port=n'      => \$port,
			'dbname=s'    => \$dbname,
			'user=s'      => \$user,
			'pass=s'      => \$pass,
			'verbose!'    => \$verbose,
			'write!'      => \$write,
			'h|help!'     => $usage,
  )
  or $usage->();

# Reading the DB connexion parameters from ~/.netrc
my $ref = Net::Netrc->lookup($host);
if ( !$ref ) {
	print STDERR "No entry found in ~/.netrc for host $host\n";
	next;
}
$user = $ref->login;
$pass = $ref->password;
$port = $ref->account;

my $dba = Bio::Vega::DBSQL::DBAdaptor->new(
											-dbname => $dbname,
											-host   => $host,
											-port   => $port,
											-user   => $user,
											-pass   => $pass,
);
my $dbc = $dba->dbc;

printf STDOUT ('-'x30)."\t%-10s\t".('-'x30)."\n",$dbname;

for my $object (('gene','transcript','exon','translation')) {

	printf STDOUT ('-'x30)."\t%-10s\n",$object;

	my $stale_id_table = $object."_stable_id";
	my $pool_table	   = $stale_id_table."_pool";
	my $sid_column     = "stable_id";
	my $pool_column    = $object."_pool_id";
	my $current_sid;

	# 1. update the *_stable_id table
	my $max_stable_id = get_max_value($stale_id_table,$sid_column,$DATE);
	next unless $max_stable_id;
	my ($species,$max_id) = $max_stable_id =~/OTT([A-Z]+)(\d+)/;
	foreach my $db_sid (@{get_all_from_date($stale_id_table,$sid_column)}) {
		my ($db_species,$db_id) = $db_sid =~/OTT([A-Z]+)(\d+)/;
		my $right_sid = sprintf("OTT%s%11s",$species,++$max_id);
		if($right_sid ne $db_sid) {
			print STDOUT "$db_sid ($right_sid) " if $verbose;
			update_stable_id($stale_id_table,$db_sid,$right_sid) if $write;
		}
	}

	# 2. update the *_stable_id_pool
	my $max_pool_id   = get_max_value($pool_table,$pool_column);
	if( !(defined $max_pool_id) || ($max_pool_id != $max_id) ) {
		printf STDOUT "\nMAX pool ID should be %d not %s\n",$max_id,$max_pool_id ? $max_pool_id : "NULL" if $verbose;
		update_pool_ids($pool_table,$pool_column,$max_id) if $write;
	}
}

sub update_stable_id {
	my ($table,$old_sid, $new_sid) = @_;
	my $sql =  qq{
		UPDATE  $table
		SET stable_id = '$new_sid'
		WHERE stable_id = '$old_sid'
		AND created_date > '$DATE'
	};
	my $sth = $dbc->prepare($sql);

	return $sth->execute();
}

sub update_pool_ids {
	my ($table,$column,$last_id) = @_;
	$dbc->do("DELETE FROM $table");
	my @ids = (1..$last_id);
	my $sql =  "INSERT INTO $table ($column)
				VALUES (".join("),(",@ids).")";
	my $sth = $dbc->prepare($sql);

	return $sth->execute();
}

sub get_values_by_sql {
	my ($sql) = @_;
	my $sth = $dbc->prepare($sql);
	my @values = ();

	$sth->execute();
	while(my ($value) = $sth->fetchrow_array()) {
		push @values, $value;
	}

	return \@values;
}

sub get_max_value {
	my ($table,$column,$date) = @_;
	my $sql =  qq{
		SELECT MAX($column)
		FROM $table
	};
	$sql .= qq{ WHERE created_date < '$date' } if $date;
	my $values = get_values_by_sql($sql);

	return shift @$values;
}

sub get_all_from_date {
	my ($table,$column) = @_;
	my $sql = qq{
		SELECT DISTINCT($column)
		FROM $table
		WHERE created_date > '$DATE'
		ORDER BY $column ASC
	};

	return get_values_by_sql($sql);
}
