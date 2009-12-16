#!/usr/local/perl/bin -w
# Author: Kerstin Jekosch
# Email: kj2@sanger.ac.uk

use strict;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Getopt::Long;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport,$file);
my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
        'file:s'   => \$file,
        );

$dbhost = 'vegabuild';
#$dbname = 'vega_danio_rerio_20070523';
$dbuser = 'ottadmin';
$dbpass = 'lutralutra';
#$dbport = 3304;

my $db = Bio::EnsEMBL::DBSQL::DBConnection->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport, 
);

my (@translationid,@transcriptid,@geneid);

die "No infile or ids provided\n" unless ($file);
if ($file) {
    open(IN,$file) or die "Cannot open infile $file $!\n";
    while (<IN>) {
        /Translation of (\d+) has stop codons/ and do {
            push @translationid, $1;
        }
    }
}
my $sth = $db->prepare(q{  select t.transcript_id, g.gene_id, g.biotype 
                            from translation tl, gene g, transcript t
                            where tl.transcript_id = t.transcript_id 
                            and t.gene_id = g.gene_id 
                            and tl.translation_id = ?
});
my (%transcriptid,%geneid);
foreach my $id (@translationid) {
    $sth->execute($id);
    ID:while (my @row = $sth->fetchrow_array) {
        unless ($row[2] eq 'protein_coding') {
            warn "biotype of gene_id ".$row[1]." is ".$row[2]."\n";
            next ID;
        }
        push @transcriptid,$row[0];
        push @geneid,$row[1];
    }    
}

my ($gcount,$tcount);
my $sth1 = $db->prepare(q{  update gene set biotype = 'protein_coding_in_progress' where gene_id = ?});
foreach my $id (@geneid) {
    $sth1->execute($id);
    $gcount++;
}
my $sth2 = $db->prepare(q{  update transcript set biotype = 'protein_coding_in_progress' where transcript_id = ?});
foreach my $id (@transcriptid) {
    $sth2->execute($id);
    $tcount++
}

my $sth3 = $db->prepare(q{delete from translation where translation_id = ?});
my $sth4 = $db->prepare(q{delete from translation_stable_id where translation_id = ?});
foreach my $id (@translationid) {
    $sth3->execute($id);
    $sth4->execute($id);
}

print "changed $gcount genes and $tcount transcripts to \'protein_coding_in_progress\'\n";


