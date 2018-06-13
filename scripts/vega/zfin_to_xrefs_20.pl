#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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


# produces xrefs for the genes listed in our weekly ZFIN downloads (see below)

use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'vegabuild';
my $user   = 'ottadmin';
#my $pass   = '**********';
my $port   = 5304;
my $dbname = 'vega_danio_rerio_20091117';

#my $host   = 'ecs3f';
#my $user   = 'ensadmin';
#my $pass   = '*******';
#my $port   = 3310;
#my $dbname = 'vega_danio_rerio_ext_20060725_v40';
BEGIN { die "Broken script; not used by Vega team" }

my $zfinfile; # lives in /lustre/cbi4/work1/zfish/ZFIN/downloads/ftp/zfin_genes.txt
my $vegafile;
my $alias;    # lives in /lustre/cbi4/work1/zfish/ZFIN/downloads/web/aliases.txt

my @chromosomes;
my $do_store = 0;

$| = 1;

&GetOptions(
  'host:s'        => \$host,
  'user:s'        => \$user,
  'dbname:s'      => \$dbname,
  'pass:s'        => \$pass,
  'port:n'        => \$port,
  'chromosomes:s' => \@chromosomes,
  'zfinfile:s'    => \$zfinfile,
  'vegafile:s'    => \$vegafile,
  'alias:s'       => \$alias, 
  'store'         => \$do_store,
);

if (scalar(@chromosomes)) {
  @chromosomes = split (/,/, join (',', @chromosomes));
}

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -pass   => $pass,
  -dbname => $dbname,
);
my $dbc = new Bio::EnsEMBL::DBSQL::DBConnection(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -pass   => $pass,
  -dbname => $dbname,
);

my $adx = $db->get_DBEntryAdaptor();


#####################################
# get names matched to ZFIN entries #
#####################################

my %crossrefs;
open(VG,$vegafile) or die "Cannot open $vegafile $!\n";
my (%zfin,%otter);
while (<VG>) {
    my ($zfinid,$name,$ottid) = split /\s+/;
    $zfin{$ottid}->{id} = $zfinid;
    $zfin{$ottid}->{name} = $name;
    push @{$otter{$name}}, $ottid;
}

open(IN,$zfinfile) or die "cannot open $zfinfile";
while (<IN>) {
    my ($zfinid,$desc,$name,$lg,$pub) = split /\t/;
    if (exists $otter{$name}) {
        foreach my $ottid (@{$otter{$name}}) {
            $zfin{$ottid}->{desc} = $desc;
        }
    }
    # create backup
    my $newname;
    if ($name =~ /si\:(\S+)/) {
        $newname = lc($1);
    }
    elsif ($name =~ /(nitr\S+)\_/) {
        $newname = $1;
    }
    else {
        $newname = $name;
    }
    $crossrefs{$newname}->{zfinid} = $zfinid;
    $crossrefs{$newname}->{desc}   = $desc;
}

# get ZFIN aliases 
open(AL,$alias) or die "cannot open $alias";
my %alias;
while (<AL>) {
    chomp;
    next unless (/ZDB-GENE/);
    my ($zfinid,$desc,$name,$alias) = split /\t/;
    $alias{$zfinid}->{$alias}++; 
}

###########################
# get gene data from vega #
###########################

my %genename;
my $sth = $dbc->prepare(q{
     select g.gene_id, x.display_label 
     from gene g, xref x 
     where g.display_xref_id = x.xref_id});
$sth->execute();
while (my @row = $sth->fetchrow_array) {
    $genename{$row[0]} = $row[1];
}

###########################################################

######################
# loop through genes #
######################

my ($firstfound,$nextfound,$nofound);
foreach my $gene_id(@{$db->get_GeneAdaptor->list_dbIDs}) {
    my $gene = $db->get_GeneAdaptor->fetch_by_dbID($gene_id);
    my $gene_id = $gene->dbID();
    my $gene_stable_id = $gene->stable_id;
    my $gene_name = $genename{$gene_id};
    
    my $newname;
    
    # nitr cases
    if ($gene_name =~ /(nitr\S+)\_/) {
        $newname = $1;
    }
    # proper CH211-234G21.3 like names
    elsif ($gene_name =~ /\S+\-\d+\D+\d+\.\d+/) {
        $newname = lc($gene_name);
    }
    # improper dZ45H12.3 like names
    elsif ($gene_name =~ /(\D+\d+\D+\d+\.\d+)/) {
        my $name = $1;
        my ($prefix,$suffix) = ($name =~ /(\D+)(\d+\D+\d+\.\d+)/); 
        if ($prefix =~ /zKp/){
            $newname = "DKEYP-".$suffix;
        }
        elsif ($prefix =~ /zK/) {
            $newname = "DKEY-".$suffix;
        }
        elsif ($prefix =~ /zC/) {
            $newname = "CH211-".$suffix;
        }
        elsif ($prefix =~ /bZ/) {
            $newname = "RP71-".$suffix;
        }
        elsif ($prefix =~ /dZ/) {
            $newname = "BUSM1-".$suffix;
        }
        elsif (($prefix =~ /bY/)  || ($name =~ /BAC/) || ($name =~ /PAC/)) {
            $newname = "XX-".$name;
        }
        else {
            $newname = $name;
        }
        
        $newname = lc($newname);
    }
    # the rest
    else {
        $newname = $gene_name;
    }
    
    
    ##################
    # create entries #
    ##################

    if ($zfin{$gene_stable_id}->{id}) {
        $firstfound++;
        &create_entry($gene,$zfin{$gene_stable_id}->{name},$zfin{$gene_stable_id}->{id},$zfin{$gene_stable_id}->{desc});
    }
         
    elsif (exists $crossrefs{$newname}) {
        $nextfound++;
        &create_entry($gene,$newname,$crossrefs{$newname}->{zfinid},$crossrefs{$newname}->{desc});
    } 
    else {
        $nofound++;
        print "No ZFIN match for $gene_name ($newname), $gene_stable_id\n";
    }
}
print "firstcount $firstfound\nsecondcount $nextfound\nnocount $nofound\n";

##################
sub create_entry {
    my $gene      = shift;
    my $gene_name = shift;
    my $zfin_id   = shift;
    my $desc      = shift;
    print "ZFIN = $gene_name, $zfin_id, $desc, ".$gene->stable_id."\n";
    my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$zfin_id,
                                         -display_id=>$gene_name,
                                         -version=>1,
                                         -release=>1,
                                         -dbname=>"ZFIN_ID",
                                        );
    $dbentry->status('KNOWN');
    $dbentry->description($desc);
    if (exists $alias{$zfin_id}) {
        print "*";
        foreach my $alias (keys %{$alias{$zfin_id}}) {
            $dbentry->add_synonym($alias);           
            print "added alias $alias to $zfin_id\n";         
        }
    }
    
    
    $gene->add_DBEntry($dbentry);
    if ($do_store) {
      $adx->store($dbentry,$gene->dbID,'Gene') or die "Couldn't store entry\n";
    }    
    #print "generated ",$dbentry->display_id(),"\n" if $do_store;

    # Display xref id update
    my $sth = $dbc->prepare("update gene set display_xref_id=" . 
                         $dbentry->dbID . " where gene_id=" . $gene->dbID);
    #print $sth->{Statement} . "\n";
    $sth->execute if $do_store;

    

}
