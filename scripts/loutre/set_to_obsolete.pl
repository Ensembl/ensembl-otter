#!/usr/bin/env perl

=head1 NAME

set_to_obsolete.pl

=head1 SYNOPSIS

set_to_obsolete.pl

=head1 DESCRIPTION

This script is used to set a gene obsolete.
Must provide a list of gene stable id.

here is an example commandline

./set_to_obsolete.pl
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
    -author	author login to lock the region of interest
    -force	proceed without user confirmation
    -help|h	displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;

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
my $force;
my $help;
my $author;
my @ids;

my $usage = sub { exec( 'perldoc', $0 ); };


GetOptions(
           'host=s'        => \$host,
           'port=n'        => \$port,
           'dbname=s'      => \$dbname,
           'user=s'        => \$user,
           'pass=s'        => \$pass,
           'author=s'	   => \$author,
           'stable_id=s'   => \@ids,
           'force'		   => \$force,
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

	my $gene = $gene_adaptor->fetch_by_stable_id($id);
	if(!$gene){
		print STDOUT "Cannot fetch gene stable id $id\n";
		next GSI;
	}
	printf STDOUT "GENE stable_id %s gene_id %d slice %s <%d-%d> strand %d author %s is_current %s\n",
					 $id, $gene->dbID,$gene->seq_region_name, $gene->seq_region_start,$gene->seq_region_end,
					 $gene->strand,$gene->gene_author->name,$gene->is_current ? 'yes':'no' ;
	if($force || &proceed() =~ /^y$|^yes$/ ) {

		my ($cb,$author_obj);
		eval {
			$cb = Bio::Vega::ContigLockBroker->new(-hostname => hostname);
			$author_obj = Bio::Vega::Author->new(-name => $author, -email => $author);
			printf STDOUT "Locking gene slice %s <%d-%d>\n",$gene->seq_region_name,$gene->seq_region_start,$gene->seq_region_end;
			$cb->lock_clones_by_slice($gene->feature_Slice,$author_obj,$db);
		};
		if($@){
			warning("Problem locking gene slice with author name $author\n$@\n");
			next GSI;
		}

		$gene->gene_author($author_obj);
		eval {
			$gene_adaptor->set_obsolete($gene);
		};
		if($@) {
			warning("Cannot make $id obsolete\n$@\n");
		} else {
			print STDOUT "gene_stable_id $id is now OBSOLETE !!!!!!\n";
		}

		eval {
			printf STDOUT "Unlocking gene slice %s <%d-%d>\n",$gene->seq_region_name,$gene->seq_region_start,$gene->seq_region_end;
			$cb->remove_by_slice($gene->feature_Slice,$author_obj,$db);
		};
		if($@){
			warning("Cannot remove locks from gene slice with author name $author\n$@\n");
		}
	} else {
		next GSI;
	}
}

sub proceed {
	print STDOUT "make this gene obsolete ? [no]";
	my $answer = <STDIN>;chomp $answer;
	$answer ||= 'no';
	return $answer;
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

