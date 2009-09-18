#!/software/bin/perl -w

=head1 NAME

rollback_gene.pl

=head1 SYNOPSIS

rollback_gene.pl

=head1 DESCRIPTION

This script is used to switch a gene back to its previous version if it exists.
First it delete the current gene then it makes the previous gene current.
Must provide a list of gene stable id.

here is an example commandline

./rollback_gene.pl
-host otterlive
-port 3352
-dbname loutre_mouse
-user ottuser
-pass *****
-stable_id OTTMUSG00000016621,OTTMUSG00000001145
-author ml6

=head1 OPTIONS

    -host (default:otterlive)   host name for the loutre database (gets put as phost= in locator)
    -dbname (no default)  For RDBs, what name to connect to (pname= in locator)
    -user (check the ~/.netrc file)  For RDBs, what username to connect as (puser= in locator)
    -pass (check the ~/.netrc file)  For RDBs, what password to use (ppass= in locator)
    -port (check the ~/.netrc file)   For RDBs, what port to use (pport= in locator)

    -stable_id	list of gene stable ids, comma separated
    -force	don't ask for confirmation
    -once	roll to the previous version only
    -author	author login to lock the region of interest
    -help|h	displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use Getopt::Long;
use Net::Netrc;
use Sys::Hostname;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::ContigLockBroker;
use Bio::Vega::Author;
use Bio::Vega::DBSQL::DBAdaptor;


my $dbname			= '';
my $host			= 'otterlive';
my $user			= '';
my $port            = '';
my $pass            = '';
my $help;
my $force;
my $once;
my $lock = 1;
my $author;
my @ids;

my $usage = sub { exec( 'perldoc', $0 ); };

my $list_sql = qq{
	SELECT g.gene_id, s.name, g.description, g.is_current, gsi.version, gsi.modified_date,a.author_name
	FROM gene g, gene_stable_id gsi,gene_author ga, seq_region s, author a
	WHERE gsi.stable_id = ?
	AND gsi.gene_id = g.gene_id
	AND s.seq_region_id = g.seq_region_id
    AND ga.gene_id = g.gene_id
    AND ga.author_id = a.author_id
	ORDER BY gsi.modified_date DESC
};

GetOptions(
           'host=s'        => \$host,
           'port=n'        => \$port,
           'dbname=s'      => \$dbname,
           'user=s'        => \$user,
           'pass=s'        => \$pass,
           'author=s'	   => \$author,
           'force!'		   => \$force,
           'once!'		   => \$once,
           'lock!'		   => \$lock,
           'stable_id=s'   => \@ids,
           'h|help!' 		   => $usage,
)
or $usage->();


throw("must provide a list of gene stable ids")
  unless ( @ids );

if ( !$user || !$pass || !$port ) {
	my @param = &get_db_param($host);
	$user = $param[0] unless $user;
	$pass = $param[1] unless $pass;
	$port = $param[2] unless $port;
}

if ( !$dbname ) {
	print STDERR
	  "Can't run script without all database parameters\n";
	print STDERR "-host $host -user $user -pass $pass\n";
	&option();
}

my $db = Bio::Vega::DBSQL::DBAdaptor->new(
    -host   => $host,
    -user   => $user,
    -dbname => $dbname,
    -pass   => $pass,
    -port   => $port
) or die ("Failed to create Bio::Vega::DBSQL::DBAdaptor to db $dbname \n");

my $gene_adaptor = $db->get_GeneAdaptor;


my @sids;
map(push(@sids , split(/,/,$_)) , @ids);

GSI: foreach my $id (@sids) {
	print "Get information for gene_stable_id $id\n";
	my $genes = &get_history($id);

	if(! defined @$genes) {
		warning("There is no gene_stable_id $id in $host:$dbname\n");
		next GSI;
	}

	my $current_gene_id = shift @$genes;

	warning("There is only one version of gene $id\n") unless @$genes;
	my $loop = 1;
	GENE:while($loop && scalar @$genes) {
		my $previous_gene_id = shift @$genes;
		my $cur_gene = $gene_adaptor->fetch_by_dbID($current_gene_id);
		my $prev_gene = $gene_adaptor->fetch_by_dbID($previous_gene_id);
		if($force || &proceed($current_gene_id) =~ /^y$|^yes$/ ) {

			my ($cb,$author_obj);
			if($lock){
				eval {
					$cb = Bio::Vega::ContigLockBroker->new(-hostname => hostname);
					$author_obj = Bio::Vega::Author->new(-name => $author, -email => $author);
					printf STDOUT "Locking gene slice %s <%d-%d>\n",$cur_gene->seq_region_name,$cur_gene->seq_region_start,$cur_gene->seq_region_end;
					$cb->lock_clones_by_slice([$cur_gene->feature_Slice,$prev_gene->feature_Slice],$author_obj,$db);
				};
				if($@){
					warning("Problem locking gene slice with author name $author\n$@\n");
					next GSI;
				}
			}

			$gene_adaptor->remove($cur_gene);
			$gene_adaptor->resurrect($prev_gene);
			print STDOUT "gene_id $current_gene_id REMOVED !!!!!!\n";

			if($lock){
				eval {
					printf STDOUT "Unlocking gene slice %s <%d-%d>\n",$cur_gene->seq_region_name,$cur_gene->seq_region_start,$cur_gene->seq_region_end;
					$cb->remove_by_slice([$cur_gene->feature_Slice,$prev_gene->feature_Slice],$author_obj,$db);
				};
				if($@){
					warning("Cannot remove locks from gene slice with author name $author\n$@\n");
				}
			}
		} else {
			last GENE;
		}
		$current_gene_id = $previous_gene_id;

		$loop = 0 if($once);
	}
}

sub proceed {
	my ( $id ) = @_;
	print STDOUT "remove gene $id ? [no]";
	my $answer = <STDIN>;chomp $answer;
	$answer ||= 'no';
	return $answer;
}


sub get_history {
	my ( $sid ) = @_;
	my $gene_ids;
	my $tag;
	my $sth = $db->dbc->prepare($list_sql);
	$sth->execute($sid);

	while(my @arr = $sth->fetchrow_array){
		print STDOUT "gene_id\tassembly name\tdescription\tis_current\tversion\tmodified_date\tauthor\n" unless $tag;
		print STDOUT join("\t",@arr)."\n";
		push @$gene_ids, $arr[0];
		$tag = 1;
	}

	return $gene_ids;
}


sub get_db_param {
	my ( $dbhost ) = @_;
	my ( $dbuser, $dbpass, $dbport );

	my $ref = Net::Netrc->lookup($dbhost);
	throw("$dbhost entry is missing from ~/.netrc") unless ($ref);
	$dbuser = $ref->login;
	$dbpass = $ref->password;
	$dbport = $ref->account;
	throw(
		"Missing parameter in the ~/.netrc file:\n
			machine " .  ( $dbhost || 'missing' ) . "\n
			login " .    ( $dbuser || 'missing' ) . "\n
			password " . ( $dbpass || 'missing' ) . "\n
			account "
		  . ( $dbport || 'missing' )
		  . " (should be used to set the port number)"
	  )
	  unless ( $dbuser && $dbpass && $dbport );

	return ( $dbuser, $dbpass, $dbport );
}

