#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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

## updated by Britt Reimholz, br2@sanger.ac.uk

# produces list of IDs for transposons and the fillers for repeat_feature
# also inserts a new entry of 'novel transposon' into repeat_consensus and adapts the repeat_consensus_id to the newly laoded entry 

use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $repeat_class;

my $dbhost = 'ensdb-web-17';
my $dbport = 5317;
my $dbuser = 'ensadmin';
#my $dbpass = '*******';
BEGIN { die "Broken - needs password" }
my $dbname;

my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
        'dbname=s' => \$dbname,
        'repeatclass:s' => \$repeat_class,
);

die "--dbanme is mandatory" unless $dbname;

# ?? insert into repeat_class values (236343,'novel_transposon','novel_transposon',\N,\N);
# ?? insert into repeat_consensus values (236343,'novel_transposon','novel_transposon','transposon',\N);


my $db = Bio::EnsEMBL::DBSQL::DBConnection->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport,
);


&help unless ($dbhost && $dbuser && $dbpass && $dbname);

my $sth10 = $db->prepare(q{select max(repeat_consensus_id) from repeat_consensus});
$sth10->execute;
while (my $no = $sth10->fetchrow_array) {
    $repeat_class = $no + 1;
}
die "need repeatclass number for novel_transposon!\n" unless ($repeat_class);
$db->do("insert into repeat_consensus values ($repeat_class,'novel_transposon','novel_transposon','transposon',\\N)");

my $sth1 = $db->prepare(q{
    select t.gene_id, 
        et.transcript_id, 
        e.exon_id, 
        e.seq_region_id, 
        e.seq_region_start, 
        e.seq_region_end, 
        e.seq_region_strand 
    from transcript t, 
        exon_transcript et, 
        exon e 
    where t.biotype = 'transposon' 
        and t.transcript_id = et.transcript_id 
        and et.exon_id = e.exon_id
});

$sth1->execute();
open(FEAT,">./repeat_feature.txt");
open(GENE,">./genes2delete_transposons.txt");

my %del;
while (my @row = $sth1->fetchrow_array) {
    print STDERR "dealing with $row[0]\n";
    my ($gid, $tid,$eid,$srid,$srstart,$srend,$srstrand) = @row;
    my $length = $srend-$srstart +1;
    print FEAT join "\t", ("\\N",$srid,$srstart,$srend,$srstrand,1,$length,$repeat_class,3,0), "\n"; 
    $del{$gid}++;
}    

foreach my $geneid (keys %del) {
    print GENE "$geneid\n";
}







#######################################################################

sub help {
    print STDERR "USAGE: \n";
}

