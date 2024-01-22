#!/usr/bin/env perl

# Copyright [2020-2024] EMBL-European Bioinformatics Institute
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

use strict;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Getopt::Long;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport);
my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
);

$dbhost = 'otterlive';
$dbname = 'loutre_zebrafish';
$dbuser ='ottro';
$dbport = 3324;

my $db = Bio::EnsEMBL::DBSQL::DBConnection->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport, 
)
;

#my $file = '/nfs/disk100/zfishpub/ZFIN/downloads/vega.txt';
my $file = $ARGV[0];
open(IN,$file) or die "Cannot open $file $!\n";
my %transcript;
while (<IN>) {
    my ($zfinid, $name,$tid) = split /\s+/;
    if ($tid =~ /OTTDART/) {
        $transcript{$tid}->{zfinid} = $zfinid;
        $transcript{$tid}->{name} = $name;
    }
    else {
        print "$zfinid\t$name\t$tid\n";
    }
}

my $sth = $db->prepare(q{
    select gsi.stable_id from transcript_stable_id tsi, transcript t, gene_stable_id gsi 
    where tsi.stable_id = ? 
    and tsi.transcript_id = t.transcript_id 
    and t.gene_id = gsi.gene_id
});

my %seen;
foreach my $tid (keys %transcript) {
    $sth->execute($tid);

    while (my @row = $sth->fetchrow_array) {
        my $gsi = $row[0]; 
        my $row = $transcript{$tid}->{zfinid}."\t".$transcript{$tid}->{name}."\t$gsi\n";
        print $row unless (exists $seen{$row});
        $seen{$row}++;
    }    
}
