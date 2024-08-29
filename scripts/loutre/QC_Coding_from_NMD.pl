#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
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

QC_Coding_from_NMD.pl

=head1 SYNOPSIS

QC_Coding_from_NMD.pl

=head1 DESCRIPTION

This script is part of a set of quality control scripts, it finds wrongly annotated 
NMD transcripts in the specified loutre database

here is an example commandline

./QC_Coding_from_NMD.pl


=head1 OPTIONS

    -host (default:otterlive)   host name for the loutre database (gets put as phost= in locator)
    -dbname (no default)  For RDBs, what name to connect to (pname= in locator)
    -user (check the ~/.netrc file)  For RDBs, what username to connect as (puser= in locator)
    -pass (check the ~/.netrc file)  For RDBs, what password to use (ppass= in locator)
    -port (check the ~/.netrc file)   For RDBs, what port to use (pport= in locator)

    -help|h	displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;

use Getopt::Long;
use Net::Netrc;
use Bio::Vega::DBSQL::DBAdaptor;

# loutre connexion parameters, default values.
my $host = 'otterlive';
my $port = '';
my $name = '';
my $user = '';
my $pass = undef;

my $usage = sub { exec( 'perldoc', $0 ); };

&GetOptions(
    'host:s'                => \$host,
    'port:n'                => \$port,
    'dbname:s'              => \$name,
    'user:s'                => \$user,
    'pass:s'                => \$pass,
    'h|help!'               => $usage
  )
  or $usage->();

if ( !$user || !$port ) {
    my @param = &get_db_param($host);
    $user = $param[0] unless $user;
    $pass = $param[1] unless $pass;
    $port = $param[2] unless $port;
}

my $tsi_sql = qq/SELECT s.name,  ga.value, gsi.stable_id, tsi.stable_id, t.seq_region_start, t.seq_region_end, t.seq_region_strand, t.biotype, t.status
FROM transcript t, transcript_stable_id tsi, gene g, gene_attrib ga, gene_stable_id gsi, seq_region s
WHERE t.biotype = 'Nonsense_mediated_decay'
AND t.status = 'UNKNOWN'
AND g.gene_id = t.gene_id
AND g.gene_id = ga.gene_id
AND ga.attrib_type_id = 4
AND gsi.gene_id = g.gene_id
AND g.is_current
AND t.is_current
AND g.source = 'havana'
AND tsi.transcript_id = t.transcript_id
AND s.seq_region_id = t.seq_region_id
ORDER BY s.name, t.seq_region_start/;

my $dba = Bio::Vega::DBSQL::DBAdaptor->new(
        -user   => $user,
        -dbname => $name,
        -host   => $host,
        -port   => $port,
        -pass   => $pass
        );
my $t_ad = $dba->get_TranscriptAdaptor;
        
my $tsi_sth = $dba->dbc->prepare($tsi_sql);
$tsi_sth->execute;

my $header = 1;
my @columns = qw{chromosome locus gene_stable_id transcript_stable_id start end strand biotype status orf(aa) stop2splice(bp)};

TRANSCRIPT: while(my ($sr_name, $locus, $gsi, $tsi, $start, $end, $strand, $biotype, $status) = $tsi_sth->fetchrow_array){
	my $t = $t_ad->fetch_by_stable_id($tsi);
	my $translation = $t->translation;
	## Condition 1 : Should have a translation (skip old NMD annotation without translation)
	next TRANSCRIPT unless $translation;
	## Condition 2 : ORF > 35aa
	my $orf_length = length($translation->seq);
	my ($CDS_start_NF) = @{ $t->get_all_Attributes('cds_start_NF') };
	## Condition 3 : Stop codon > 50bases from last splice junction
	my $exons = $t->get_all_Exons();
	my $last_coding_exon = $translation->end_Exon();
	my $last_coding_exon_end = $translation->end();
	pop @$exons; # remove last exon
	my $stop_to_splice = 0;
	my $flag;
	EXON: foreach(@$exons){
		next EXON unless ($_ eq $last_coding_exon || $flag);
		if($_ eq $last_coding_exon) {
		  $stop_to_splice = $_->seq->length - $last_coding_exon_end;
		  $flag = 1;
		  next EXON;	
		}
		$stop_to_splice += $_->seq->length;
	}
	## Condition 4 : CDS variant reference ?
	
	## Print transcript info if it reaches this point 
	
	print STDOUT join("\t",@columns)."\n" 
	   if $header;
	$header = 0;
	
	print STDOUT join(" ",$sr_name, $locus, $gsi, $tsi, $start, $end, $strand, $biotype, $status,$orf_length,$stop_to_splice)."\n" 
	   if(( $orf_length <= 35 && !$CDS_start_NF) || $stop_to_splice <= 50);
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

