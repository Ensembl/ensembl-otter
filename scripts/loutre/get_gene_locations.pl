#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


=head1 NAME

get_gene_locations.pl

=head1 SYNOPSIS

get_gene_locations.pl

=head1 DESCRIPTION

This script prints chromosome and clone locations for a list of gene stable ids
that is either provided as command line option or fetched using a gene description key

here is an example commandline

./get_gene_location.pl
-host otterlive
-port 3324
-dbname loutre_human
-user pipuser
-pass *****

-stable_id OTTHUMG00000000399,OTTHUMG00000000400,...
or
-desc 'DUF622'


=head1 OPTIONS

    -host (default:otterlive)   host name of the database with missing contig dna
    -dbname (no default)  For RDBs, what database to connect to
    -user (check the ~/.netrc file)  For RDBs, what username to connect as
    -pass (check the ~/.netrc file)  For RDBs, what password to use
    -port (check the ~/.netrc file)   For RDBs, what port to use

    -stable_id  comma separated list of gene stable id
    -desc       get all genes with a description containing this world

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;
use Sys::Hostname;
use Net::Netrc;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Vega::Utils::Comparator qw(compare);
use Bio::Otter::Lace::Defaults;
use Getopt::Long;
use HTTP::Date;

my $dbname;
my $host = 'otterlive';
my $port;
my $user;
my $pass;
my @ids;
my $desc;

my $usage   = sub { exec( 'perldoc', $0 ); };
    
GetOptions(
            'host=s'      => \$host,
            'port=n'      => \$port,
            'dbname=s'    => \$dbname,
            'user=s'      => \$user,
            'pass=s'      => \$pass,
            'desc=s'      => \$desc,
            'stable_id=s' => \@ids,
            'h|help!'     => $usage,
  )
  or $usage->();

throw("Must provide a database name (dbname) !") 
    unless $dbname;

throw("Must either provide a list of stable id or a description key world !") 
    unless @ids || $desc;
    
if(!$user || !$port){    
	# Reading the DB connexion parameters from ~/.netrc
	my $ref = Net::Netrc->lookup($host);
	if ( !$ref ) {
	    print STDERR "No entry found in ~/.netrc for host $host\n";
	    next;
	}
	$user ||= $ref->login;
	$pass ||= $ref->password;
	$port ||= $ref->account;
}

my @sids;
map( push( @sids, split( /,/, $_ ) ), @ids );

my $dba = Bio::Vega::DBSQL::DBAdaptor->new(
                                            -dbname => $dbname,
                                            -host   => $host,
                                            -port   => $port,
                                            -user   => $user,
                                            -pass   => $pass,
);

my $ga = $dba->get_GeneAdaptor();

my $list = @sids ?  \@sids : &get_desc_list($ga->dbc, $desc);
my $header = 0;
GSI: foreach my $si ( sort @$list ) {
    my $gene = $ga->fetch_latest_by_stable_id($si);
    next unless $gene;
    my $gene_slice = $gene->feature_Slice;
    my $desc       = $gene->description;
    my $chr_name   = $gene_slice->seq_region_name;
    my $chr_start  = $gene->start;
    my $chr_end    = $gene->end;
    my $chr_strand = $gene->strand;
    
    my $clone_projection = $gene_slice->project('clone');
    
    my @clones = ();
    foreach my $seg (@$clone_projection) {
      my $clone = $seg->to_Slice();
      my $clone_name   = $clone->seq_region_name();
      my $clone_start  = $clone->start();
      my $clone_end    = $clone->end();
      my $clone_strand = $clone->strand();
      push @clones,join(":",$clone_name,$clone_start,$clone_end,$clone_strand);
    }
    
    my $format = "%-20s %-15s %-10s %-10s %-6s %-30s %-60s\n";
    # print table header here
    printf STDOUT $format,
        "gene_stable_id","chromosome","start","end","strand","clone:start:end:strand","description"
            unless $header;$header =1;
    # print the rows here
    printf STDOUT $format,
        $si,$chr_name,$chr_start,$chr_end,$chr_strand,shift @clones,$desc;
    while(my $c = shift @clones) {
    	 printf STDOUT "%66s%-30s\n","",$c;
    }
}


# Start the methods here

sub get_desc_list {
	my ($dbc, $desc) = @_;
	my $desc_sql = qq{
	        SELECT DISTINCT(gsi.stable_id)
	        FROM gene g, gene_stable_id gsi
	        WHERE g.description LIKE '%$desc%'
	        AND g.is_current
	        AND g.gene_id = gsi.gene_id;
	};
	my $sid;
	my $desc_sth = $dbc->prepare($desc_sql);
	$desc_sth->execute();
	while(my $a = $desc_sth->fetchrow_arrayref){
	   push @$sid, @$a;
    }
		
	return $sid;
}
