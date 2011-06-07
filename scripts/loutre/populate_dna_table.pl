#!/usr/bin/env perl

BEGIN {
    foreach my $path (@INC) {
        $path=~s{ensembl/modules}{ensembl_head/modules}g;
        $path=~s{ensembl-pipeline/modules}{ensembl-pipeline_head/modules}g;
    }
}

# PROGRAM  : populate_dna_table.pl.pl
# PURPOSE  :
# AUTHOR   : Mustapha Larbaoui ml6@sanger.ac.uk
# CREATED  : Mar 22, 2007 11:32:21 AM

=head1 NAME

populate_dna_table.pl

=head1 SYNOPSIS

populate_dna_table.pl

=head1 DESCRIPTION

This script is used to repopulate the missing dna sequences in the dna table
based on the contigs already loaded in the seq_region table. It gets the
dna either from an ensembl source database if specified or from the pfetch server.

here is an example commandline

./populate_dna_table.pl
-host otterpipe2
-port 3352
-dbname pipe_human
-user pipuser
-pass *****

=head1 OPTIONS

    -host (default:otterlive)   host name of the database with missing contig dna
    -dbname (no default)  For RDBs, what database to connect to
    -user (check the ~/.netrc file)  For RDBs, what username to connect as
    -pass (check the ~/.netrc file)  For RDBs, what password to use
    -port (check the ~/.netrc file)   For RDBs, what port to use

    -shost (default:otterpipe1)   host name of the source database
    -sdbname (no default)  For RDBs, what database to connect to
    -suser (check the ~/.netrc file)  For RDBs, what username to connect as
    -spass (check the ~/.netrc file)  For RDBs, what password to use
    -sport (check the ~/.netrc file)   For RDBs, what port to use


    -chunk_size	maximum number of sequences to retrieve from pfetch at one time
    -help|h	displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;

use DBI;
use Getopt::Long;
use Net::Netrc;
use Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

my $user;
my $pass;
my $port;
my $host = 'otterlive';
my $dbname;

my $suser;
my $spass;
my $sport;
my $shost = 'otterpipe1';
my $sdbname;

my $dsn;
my $dbh;

my $sql_select = "	SELECT s.seq_region_id,  substring(s.name,1,length(s.name)-(length(substring_index(s.name,'.',-2))+1)), s.name
					FROM coord_system c
					LEFT JOIN seq_region s ON c.coord_system_id = s.coord_system_id
					LEFT JOIN dna d ON d.seq_region_id = s.seq_region_id
					WHERE  c.name = 'contig'
					AND d.seq_region_id IS NULL
					ORDER BY s.seq_region_id ASC";
my $sql_insert = "	INSERT IGNORE INTO dna
					( seq_region_id , sequence )
					VALUES ";

my $chunk_size;
my $usage = sub { exec( 'perldoc', $0 ); };


GetOptions(
           'host=s'        => \$host,
           'port=n'        => \$port,
           'dbname=s'      => \$dbname,
           'user=s'        => \$user,
           'pass=s'        => \$pass,
           'shost=s'        => \$shost,
           'sport=n'        => \$sport,
           'sdbname=s'      => \$sdbname,
           'suser=s'        => \$suser,
           'spass=s'        => \$spass,
           'chunk_size'	   => \$chunk_size,
           'h|help!' 	   => $usage
	) or $usage->();

if ( !$dbname ) {
	print STDERR
	  "Need a target pipeline database name\n";
	print STDERR "-host $host -user $user -pass $pass\n";
}

$chunk_size ||= 20;

# Reading the target DB connexion parameters from ~/.netrc
my $ref = Net::Netrc->lookup($host);
if ( !$ref ) {
	print STDERR "No entry found in ~/.netrc for host $host\n";
	next;
}
$user = $ref->login;
$pass = $ref->password;
$port = $ref->account;

# Reading the source DB connexion parameters from ~/.netrc
$ref = Net::Netrc->lookup($shost);
if ( !$ref ) {
	print STDERR "No entry found in ~/.netrc for host $shost\n";
	next;
}
$suser = $ref->login;
$spass = $ref->password;
$sport = $ref->account;

# Creating the target DB connexion
$dsn = "DBI:mysql:database=$dbname;host=$host;port=$port";
$dbh = DBI->connect( $dsn, $user, $pass, { 'RaiseError' => 1 } );
my $sth;

print STDOUT "Get contigs with missing dna from $host - > $dbname\n";

# Get the missing sequence accessions
my $db_sth = $dbh->prepare($sql_select);
$db_sth->execute()
	  or die "Couldn't execute statement: " . $db_sth->errstr;

# create accession -> dbid hash
my %clone_dbid;
while ( my ($dbid, $clone, $contig) = $db_sth->fetchrow_array() ) {
	$clone_dbid{$clone} = [$contig,$dbid];
}

my @clones = sort { $clone_dbid{$a}->[1] <=> $clone_dbid{$b}->[1] } keys %clone_dbid;
print STDOUT "Found ".scalar(@clones)." contigs with missing DNA in $host:$dbname\n";
print STDOUT "Get dna from ";
if($sdbname) {
	print STDOUT "source database $shost:$sdbname\n";
	my $source_dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        -user   => $suser,
        -dbname => $sdbname,
        -host   => $shost,
        -pass   => $spass,
        -port   => $sport);
	my $sa = $source_dba->get_SliceAdaptor;
	$sth = $dbh->prepare($sql_insert." (?, ?) ");
	foreach my $clone (@clones){
		my $contig = $clone_dbid{$clone}->[0];
		my $dbid = $clone_dbid{$clone}->[1];
		my $contig_slice = $sa->fetch_by_region('contig', $contig);
		die("Cannot fetch contig [$contig] from $shost:$sdbname") unless $contig_slice;
		my $seq = $contig_slice->seq();
		print STDOUT "Save $contig contig dna\n" if $seq;
		$sth->execute($dbid,$seq) or die "Couldn't execute statement: " . $sth->errstr;
	}
	$sth->finish();
} else {
	print STDOUT "Pfetch server\n";
	for (my $i = 0; $i < @clones; $i += $chunk_size) {
		my $j = $i + $chunk_size - 1;
		# Set second index to last element if we're off the end of the array
	    $j = $#clones if $#clones < $j;
	    # Take a slice from the array
	    my $chunk = [@clones[$i..$j]];
		# Retrieve the sequences
		my $seqfetcher = Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new;
		my @seqs = $seqfetcher->get_Seq_by_acc(@$chunk);
		my (@binds, @values);
		my $sql;
		print STDOUT "Save ".scalar(@seqs)." contig dna\n" if @seqs;
		for my $seq (@seqs) {
			next unless defined $seq;
			push(@binds, $clone_dbid{$seq->accession_number}->[1], $seq->seq);
			push(@values, qq{ (?, ?)});
			#print STDOUT $seq->accession_number." ";
		}

	    if(scalar(@values)) {
			$sql .= join(", ", @values);
			$sth = $dbh->prepare($sql_insert.$sql);
			$sth->execute(@binds) or die "Couldn't execute statement: " . $sth->errstr;
			$sth->finish();
	    }
	}
}

