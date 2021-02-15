#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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

# Author: Kerstin Jekosch
# Email: kj2@sanger.ac.uk

# updated by Britt Reimholz, br2@sanger.ac.uk

## amended the code to also delete appropriate xref_ids from xref and object_xref
## and delete entries in object_xref, xref and translation_stable_id where translation_id is null

use strict;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Getopt::Long;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport,$file);

$dbhost = 'vegabuild';
#$dbname = 'vega_danio_rerio_20070523';
$dbuser = 'ottadmin';
#$dbpass = '**********';
#$dbport = 3304;
BEGIN { die "Broken script; not used by Vega team" }

my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
        'file:s'   => \$file,
        );

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
my ($oxref_count,$xref_count, $translation_stable_count);

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

my $sth5 = $db->prepare(qq{ select xref_id from object_xref ox where  
                  ensembl_object_type = 'Translation' and ensembl_id = ? });
my $sth6 = $db->prepare(qq{delete from xref where xref_id = ?});
my $sth7 = $db->prepare(qq{delete from object_xref where ensembl_object_type = 'Translation' and ensembl_id = ?});

foreach my $id (@translationid) {
    $sth3->execute($id);
    $sth4->execute($id);

    $sth5->execute($id);
    while (my @row = $sth5->fetchrow_array) {
        my $xref_id = $row[0];
	$sth6->execute($xref_id);
	$xref_count++;
    }
    $sth7->execute($id);
    $oxref_count++;
}

print "changed $gcount genes and $tcount transcripts to \'protein_coding_in_progress\'\n";


## delete entries in object_xref, xref and translation_stable_id where 
## translation id is null 
my $sth8 = $db->prepare(qq{ select tsi.translation_id 
                    from translation_stable_id tsi left join translation t 
		    on tsi.translation_id = t.translation_id 
		    where t.translation_id is null });
$sth8->execute();

while (my @row = $sth8->fetchrow_array) {
    my $translation_id = $row[0];    
    $sth4->execute($translation_id);
    $translation_stable_count++;
    
    $sth5->execute($translation_id);
    while (my @row = $sth5->fetchrow_array) {
        my $xref_id = $row[0];
	$sth6->execute($xref_id);
	$xref_count++;
    }
    $sth7->execute($translation_id);
    $oxref_count++;
}

print "deleted $oxref_count object_xrefs with object_type \'Translation\' and $xref_count xrefs \n";
