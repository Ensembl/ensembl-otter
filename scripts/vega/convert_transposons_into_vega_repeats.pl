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

# Author: Kerstin Jekosch
# Email: kj2@sanger.ac.uk

# produces list of IDs for transposons and the fillers for repeat_feature

use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport,$repeat_class);
my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
        'repeatclass:s' => \$repeat_class,
);

$dbhost = 'ecs4';
$dbport = 3351;
$dbuser = 'ensadmin';
#$dbpass = '*******';
BEGIN { die "Broken - needs password" }
$dbname = 'zfish_vega_1104';
$repeat_class = 75664;

my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport,
);


&help unless ($dbhost && $dbuser && $dbpass && $dbname);
die "need repeatclass number for novel_transposon!\n" unless ($repeat_class);

my $sth1 = $db->prepare(q{
    select t.gene_id, 
        et.transcript_id, 
        e.exon_id, 
        e.contig_id, 
        e.contig_start, 
        e.contig_end, 
        e.contig_strand 
    from transcript_class tc, 
        transcript_info ti, 
        transcript_stable_id tsi, 
        transcript t, 
        exon_transcript et, 
        exon e 
    where tc.name = 'Transposon' 
        and tc.transcript_class_id = ti.transcript_class_id 
        and ti.transcript_stable_id = tsi.stable_id 
        and tsi.transcript_id = t.transcript_id 
        and t.transcript_id = et.transcript_id 
        and et.exon_id = e.exon_id
});

$sth1->execute();

my %del;
while (my @row = $sth1->fetchrow_array) {
    my ($gid, $tid,$eid,$cid,$cstart,$cend,$cstrand) = @row;
    my $length = $cend-$cstart +1;
    print join "\t", ("\\N",$cid,$cstart,$cend,$cstrand,1,$length,$repeat_class,5000,0), "\n"; 
    $del{$gid}++;
}    

foreach my $geneid (keys %del) {
    print "$geneid\n";
}







#######################################################################

sub help {
    print STDERR "USAGE: \n";
}

