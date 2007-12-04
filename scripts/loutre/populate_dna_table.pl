#!/software/bin/perl -w

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
based on the contigs already loaded in the seq_region table.

here is an example commandline

./populate_dna_table.pl
-host otterpipe2
-port 3352
-dbname pipe_human
-user pipuser
-pass *****

=head1 OPTIONS

    -host (default:otterpipe1)   host name of the target database (gets put as phost= in locator)
    -dbname (no default)  For RDBs, what database to connect to (pname= in locator)
    -user (check the ~/.netrc file)  For RDBs, what username to connect as (puser= in locator)
    -pass (check the ~/.netrc file)  For RDBs, what password to use (ppass= in locator)
    -port (check the ~/.netrc file)   For RDBs, what port to use (pport= in locator)

    -chunk_size	maximum number of sequences to retrieve from pfetch at one time
    -help|h	displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use DBI;
use Getopt::Long;
use Net::Netrc;
use Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch;

my $user;
my $pass;
my $port;
my $host;
my $dbname;

my $dsn;
my $dbh;

my $sql_select = "	SELECT s.seq_region_id, substring_index(s.name,'.',2)
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
           'chunk_size'	   => \$chunk_size,
           'h|help!' 	   => $usage
	) or $usage->();

if ( !$dbname ) {
	print STDERR
	  "Need a target pipeline database name\n";
	print STDERR "-host $host -user $user -pass $pass\n";
}

$chunk_size ||= 20;

# Reading the DB connexion parameters from ~/.netrc
my $ref = Net::Netrc->lookup($host);
if ( !$ref ) {
	print STDERR "No entry found in ~/.netrc for host $host\n";
	next;
}
$user = $ref->login;
$pass = $ref->password;
$port = $ref->account;

# Creating the DB connexion
$dsn = "DBI:mysql:database=$dbname;host=$host;port=$port";
$dbh = DBI->connect( $dsn, $user, $pass, { 'RaiseError' => 1 } );

print STDOUT "Get dbID accessions from $host - > $dbname\n";

# Get the missing sequence accessions
my $db_sth = $dbh->prepare($sql_select);
$db_sth->execute()
	  or die "Couldn't execute statement: " . $db_sth->errstr;

# create accession -> dbid hash
my %acc_dbid;
while ( my ($dbid,$acc) = $db_sth->fetchrow_array() ) {
	$acc_dbid{$acc} = $dbid;
}

print STDOUT "Save sequences into $host - > $dbname / dna\n";

# Pfetch accessions and save sequences into dna table
my @accessions = sort { $acc_dbid{$a} <=> $acc_dbid{$b} } keys %acc_dbid;
for (my $i = 0; $i < @accessions; $i += $chunk_size) {
	my $j = $i + $chunk_size - 1;
	# Set second index to last element if we're off the end of the array
    $j = $#accessions if $#accessions < $j;
    # Take a slice from the array
    my $chunk = [@accessions[$i..$j]];
	# Retrieve the sequences
	my $seqfetcher = Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new;
	my @seqs = $seqfetcher->get_Seq_by_acc(@$chunk);
	my (@binds, @values);
	my $sql;
	my $sth;
	print STDOUT "Save Accessions: ";
	for my $seq (@seqs) {
		next unless defined $seq;
		push(@binds, $acc_dbid{$seq->accession_number}, $seq->seq);
		push(@values, qq{ (?, ?)});
		print STDOUT $seq->accession_number." ";
	}
	print STDOUT "\n";

    if(scalar(@values)) {
		$sql .= join(", ", @values);
		$sth = $dbh->prepare($sql_insert.$sql);
		$sth->execute(@binds) or die "Couldn't execute statement: " . $sth->errstr;
		$sth->finish();
    }
}




