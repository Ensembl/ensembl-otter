#!/usr/local/bin/perl
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

# creates the necessary data to be put onto ftp.sanger.ac.uk/pub/kj2 for ZFIN

# KERSTIN HOWE PROUDLY PRESENTS: THE MOST HORRIBLE SCRIPT EVER!!!


use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Getopt::Long;

my $dbhost = 'ensdb-web-17';
my $dbuser = 'ensro';
my $dbname = 'vega_danio_rerio_20151019_82_GRCz10';
my $dbpass = '';
my $dbport = 5317;
#my $dbhost = 'ecs3f';
#my $dbuser = 'ensro';
#my $dbname = 'vega_danio_rerio_ext_20060725_v40';
#my $dbpass = '';
#my $dbport = 3310;

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
);
my $dbc = Bio::EnsEMBL::DBSQL::DBConnection->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport,
);

# gene data

my $sth1 = $dbc->prepare(q{
    select x.dbprimary_acc, x.display_label, ox.ensembl_id 
    from xref x, object_xref ox, external_db ed 
    where ed.external_db_id = 2510 
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

my %name;
my $sth1a = $dbc->prepare(q{
    select g.stable_id, ga.value
    from gene g, gene_attrib ga
    where g.gene_id = ga.gene_id and ga.attrib_type_id = 4
});
$sth1a->execute();
while (my @row = $sth1a->fetchrow_array) {
    $name{$row[0]} = $row[1];
}

my %link;
my $slice_adaptor = $db->get_SliceAdaptor();
foreach my $gene_id(@{$db->get_GeneAdaptor->list_dbIDs}) {
        my $gene = $db->get_GeneAdaptor->fetch_by_dbID($gene_id);
        my $gene_id = $gene->dbID();
        my $gene_stable_id = $gene->stable_id;
        my $gene_version   = $gene->version;
        
        my $slice = $slice_adaptor->fetch_by_region($gene->slice->coord_system->name,
                                                    $gene->slice->seq_region_name,
                                                    $gene->start,
                                                    $gene->end,
                                                    undef,
                                                    $gene->slice->coord_system->version);
        my $components = $slice->project('clone');
        my @clones;
        foreach my $comp (@$components) {
            push @clones, $comp->to_Slice->seq_region_name;
        }
        my $clone = join ",", @clones;
                             
        my $gene_name = $name{$gene_stable_id}; 
        my $gene_type = $gene->biotype;
        my $gene_status = $gene->status;
        my $type = $gene_type.".".$gene_status;
        

        push @{$link{$gene_id}}, [$gene_name,$gene_stable_id,$clone,$type,$gene_version];
}


open(GENE,">./genes_for_tom.txt") or die "Cannot open ./genes_for_tom.txt $!\n";
my $count;
foreach my $id (keys %link) {
    foreach my $entry (@{$link{$id}}) {
        if (exists $zfinid{$id}) {
            unless ($zfinid{$id}[1] =~ /^si\:/) {
                print STDERR "gene_name.name $entry->[0] != xref.display_label $zfinid{$id}[1]\n" unless (($entry->[0] eq $zfinid{$id}[1]) || ($entry->[0] =~ /$zfinid{$id}[1]/i));
                $count++ unless ($entry->[0] =~ /$zfinid{$id}[1]/i);
            }
            # otter ID, clone, type, zfin ID, gene symbol
            print GENE "$entry->[0]\t$entry->[1]\t$entry->[2]\t$entry->[3]\t$zfinid{$id}[0]\t$zfinid{$id}[1]\n";
        }
        else {
            print GENE "$entry->[0]\t$entry->[1] version $entry->[4]\t$entry->[2]\t$entry->[3]\n";
        }
    }
}
print STDERR "$count genes have different entry in gene_name.name and xref.display_label that has to be sorted at some point in in re-annotation, no need to worry now.\n";


# annotated clones
my $sth4 = $dbc->prepare(q{
    select substring_index(sr.name,'.',2)
    from seq_region sr, seq_region_attrib sra
    where sr.seq_region_id = sra.seq_region_id
    and sra.attrib_type_id = 121 and sra.value = 'T'
});    
$sth4->execute();
my %anno;
while (my @row = $sth4->fetchrow_array) {
    $anno{$row[0]}++;
}


# clones on chromosomes (horrible, but anyway...)
my %clonename;
my $sth3 = $dbc->prepare(q{
     select sra.value, substring_index(sr2.name,'.',2), sr3.name 
     from seq_region_attrib sra, seq_region sr1, seq_region sr2, seq_region sr3, assembly a
     where sra.seq_region_id = sr1.seq_region_id 
     and sr1.coord_system_id = 2 # clone
     and sr1.name = substring_index(sr2.name,'.',2) 
     and sr2.coord_system_id = 3 # contig
     and sr2.seq_region_id = a.cmp_seq_region_id 
     and a.asm_seq_region_id = sr3.seq_region_id 
     and sr3.coord_system_id = 1  # chromosome
     and sra.value like '%-%'
});
$sth3->execute();

open(CL,">./clonelist_for_tom.txt") or die "Cannot open ./clonelist_for_tom.txt $!\n";
while (my @row = $sth3->fetchrow_array) {
    $clonename{$row[1]} = $row[0];
    my $chr = $row[2];
#    my ($chr) = ($row[2] =~ /chr(\d+)\_/);
    print CL "$row[0]\t$row[1]\t$chr";
    if (exists $anno{$row[1]}) {
        print CL "\tannotated";
    }
    print CL "\n";
}

# assembly data

my $sth5 = $dbc->prepare(q{
    select sr1.name, a.asm_start, a.asm_end, substring_index(sr2.name,'.',2), a.cmp_start, a.cmp_end, a.ori 
    from seq_region sr1, assembly a, seq_region sr2 
    where sr1.coord_system_id = 1
    and sr1.seq_region_id = a.asm_seq_region_id 
    and sr2.coord_system_id = 3 
    and sr2.seq_region_id = a.cmp_seq_region_id 
    order by sr1.name, a.asm_start
});
$sth5->execute();
open(ASS, ">./assembly_for_tom.txt") or die "Cannot open ./assembly_for_tom.txt $!\n";
while (my @row = $sth5->fetchrow_array) {
    next if ($row[0] eq 'H');
    my $chr = $row[0];
    my $clonename = $clonename{$row[3]};
    print ASS "$chr\t$row[1]\t$row[2]\t$clonename\t$row[3]\t$row[4]\t$row[5]\t$row[6]\n";
}
