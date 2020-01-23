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

# creates the necessary data to be put onto ftp.sanger.ac.uk/pub/kj2 for ZFIN

use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport);
my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
);

my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport,
)
;


my $sth1 = $db->prepare(q{
    select x.dbprimary_acc, x.display_label, ox.ensembl_id 
    from xref x, object_xref ox, external_db ed 
    where ed.external_db_id = 4 
    and x.xref_id = ox.xref_id 
    and ox.ensembl_object_type = 'Gene' 
    and x.dbprimary_acc like 'ZDB%';
});

$sth1->execute();

my %zfinid;
while (my @row = $sth1->fetchrow_array) {
    my ($zfinid,$name,$ensid) = @row;
    $zfinid{$ensid} = [$zfinid,$name];
}    

my $sth2 = $db->prepare(q{
    select distinct g.gene_id, gn.name, gsi.stable_id, cl.name, g.type 
    from gene_name gn, gene g, gene_stable_id gsi, gene_info gi, transcript t, exon_transcript et, exon e, contig c, clone cl 
    where g.gene_id =  gsi.gene_id  
    and gsi.stable_id = gi.gene_stable_id 
    and gi.gene_info_id = gn.gene_info_id 
    and g.gene_id = t.gene_id 
    and t.transcript_id = et.transcript_id 
    and et.exon_id = e.exon_id 
    and e.contig_id = c.contig_id 
    and c.clone_id = cl.clone_id;
});

$sth2->execute();

my %link;
while (my @row = $sth2->fetchrow_array) {
    my ($ensid,$name, $otterid,$clone, $type) = @row;
    push @{$link{$ensid}}, [$name,$otterid,$clone,$type];

}

open(GENE,">./genes_for_tom.txt") or die "Cannot open ./genes_for_tom.txt $!\n";
my $count;
foreach my $id (keys %link) {
    foreach my $entry (@{$link{$id}}) {
        if (exists $zfinid{$id}) {
            unless ($zfinid{$id}[1] =~ /^si\:/) {
                print STDERR "gene_name.name $entry->[0] != xref.display_label $zfinid{$id}[1]\n" unless ($entry->[0] eq $zfinid{$id}[1]);
                $count++;
            }
            # otter ID, clone, type, zfin ID, gene symbol
            print GENE "$entry->[1]\t$entry->[2]\t$entry->[3]\t$zfinid{$id}[0]\t$zfinid{$id}[1]\n";
        }
        else {
            print GENE "$entry->[1]\t$entry->[2]\t$entry->[3]\n";
        }
    }
}
print STDERR "$count genes have different entry in gene_name.name and xref.display_label that has to be sorted at some point in in re-annotation, no need to worry now.\n";


my $sth3 = $db->prepare(q{
    select cl.name, cl.embl_acc, c.name 
    from clone cl, contig ct, assembly a, chromosome c 
    where cl.clone_id = ct.clone_id 
    and ct.contig_id = a.contig_id 
    and a.chromosome_id = c.chromosome_id 
});
$sth3->execute();
open(CL,">./clonelist_for_tom.txt") or die "Cannot open ./clonelist_for_tom.txt $!\n";
while (my @row = $sth3->fetchrow_array) {
    print CL join "\t", @row,"\n";
}

my $sth4 = $db->prepare(q{
    select ctg.name, cl.name 
    from chromosome chr, assembly a, contig ctg, clone cl, clone_info ci, clone_remark cr 
    where chr.chromosome_id =a.chromosome_id 
    and a.contig_id = ctg.contig_id 
    and ctg.clone_id = cl.clone_id 
    and ctg.clone_id = ci.clone_id 
    and ci.clone_info_id = cr.clone_info_id 
    and cr.remark like '%annotated%' 
});
$sth4->execute();
open(ANN,">./annotated_clones.txt") or die "Cannot open ./annotated_clones.txt $!\n";
while (my @row = $sth4->fetchrow_array) {
    print ANN join "\t", @row, "\n";
}

my $sth5 = $db->prepare(q{
    select chr.name, a.chr_start, a.chr_end, cl.name, substring_index(c.name,'.',2), a.contig_start, a.contig_end,a.contig_ori 
    from assembly a, chromosome chr, contig c, clone cl 
    where chr.chromosome_id = a.chromosome_id 
    and a.contig_id = c.contig_id 
    and c.clone_id = cl.clone_id 
});
$sth5->execute();
open(ASS, ">./assembly_for_tom.txt") or die "Cannot open ./assembly_for_tom.txt $!\n";
while (my @row = $sth5->fetchrow_array) {
    print ASS join "\t", @row, "\n";
}
