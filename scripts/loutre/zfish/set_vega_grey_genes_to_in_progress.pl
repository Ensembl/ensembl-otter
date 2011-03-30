#!/usr/bin/perl -w
use strict;

use Bio::Otter::DBSQL::DBAdaptor;

my $dbname = 'otter_zebrafish';
my $dbhost = 'otterlive';
my $dbport =  3301;
my $dbuser = 'ottro';
my $dbpass = '';

my $db = new Bio::Otter::DBSQL::DBAdaptor(
        -dbname  => $dbname,
        -host    => $dbhost,
        -port    => $dbport,
        -user    => $dbuser,
        -pass    => $dbpass,
);

my $g_ad = $db->get_GeneAdaptor();

my $file = $ARGV[0];
open (FILE, $file) or die "Can't open $file:$!";

my %grey;
while (my $line = <FILE>) {
    
    if ($line =~ m/Failed to find \d+ bp exon \'(\w+)\'/) {
	my $exon = $1;
	my $gene = $g_ad->fetch_by_exon_stable_id($exon);
	$grey{$gene->stable_id}{$exon} = 1;
    }
}


print "select * from gene_stable_id join gene using (gene_id) where stable_id in (".join("\', \'", keys %grey)."\');\n\n";

print "if this looks ok- should be only latest version- then change biotype:\n";
print "update gene join gene_stable_id using (gene_id) set biotype = 'protein_coding_in_progress'  where stable_id in (".join("\', \'", keys %grey)."\');\n\n";

