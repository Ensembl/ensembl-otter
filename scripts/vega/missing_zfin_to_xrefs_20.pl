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


# same as missing_zfin_to_xrefs.pl but for schema 20+

use strict;


use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs3d';
my $user   = 'ensadmin';
#my $pass   = '*******';
BEGIN { die "Broken - needs password" }
my $port   = 3307;
my $dbname = 'vega_danio_rerio_core_23_7';
my $zfinfile;

my $path = 'VEGA';
my $do_store = 0;

$| = 1;

&GetOptions(
  'host:s'        => \$host,
  'user:s'        => \$user,
  'dbname:s'      => \$dbname,
  'pass:s'        => \$pass,
  'path:s'        => \$path,
  'port:n'        => \$port,
  'zfinfile:s'     => \$zfinfile,
  'store'         => \$do_store,
);


my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -pass   => $pass,
  -dbname => $dbname
);
#$db->assembly_type($path);

my $aga = $db->get_GeneAdaptor();
my $adx = $db->get_DBEntryAdaptor();


# get names matched to ZFIN entries
my %crossrefs;
open(IN,$zfinfile) or die "cannot open $zfinfile";
while (<IN>) {
    my ($zfinid,$name,$ottid) = split /\t/;
    $crossrefs{$ottid}->{zfinid} = $zfinid;
    $crossrefs{$ottid}->{name}   = $name;
}

foreach my $ottid (keys %crossrefs) {
    my $gene = $aga->fetch_by_stable_id($ottid);

    print "Fetching $ottid\n";
    my $foundottid = $gene->stable_id;
    if (exists $crossrefs{$foundottid}) {
        my $gene_name;
        if ($gene->display_id) {
            $gene_name = $gene->external_name;
            print "Taking $gene_name as gene_name\n";
        } 
        else {
            die "Failed finding gene name for " .$gene->stable_id . "\n";
        }

        # test whether entry already existent and next
        my @db_entries = @{$adx->fetch_all_by_Gene($gene)};
        my $found;
        foreach my $entry (@db_entries) {
            if ($entry->dbname eq 'ZFIN') {
                $found++;
                if ($entry->primary_id eq $crossrefs{$foundottid}->{zfinid}) {
                    print "same entries, skipping\n";
                }
                else {
                    print "ERROR: ",$gene->stable_id," should be ",$crossrefs{$foundottid}->{zfinid}," but is ",$entry->primary_id,"\n";
                }
            }
        }


        # make new entry unless found
        unless ($found) {
            print "couldn't find ZFIN entry for ",$gene->stable_id,", have to make one: ",$crossrefs{$foundottid}->{zfinid},",\n";
            my $id = $crossrefs{$foundottid}->{zfinid};
            my $display = $crossrefs{$foundottid}->{name};
            
            my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$id,
                                                     -display_id=>$display,
                                                     -version=>1,
                                                     -release=>1,
                                                     -dbname=>"ZFIN",
                                                    );
            $dbentry->status('KNOWNXREF');
            $gene->add_DBEntry($dbentry);
            $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;

            # Display xref id update
            my $sth = $db->prepare("update gene set display_xref_id=" . 
                                     $dbentry->dbID . " where gene_id=" . $gene->dbID);
            print $sth->{Statement} . "\n";
            $sth->execute if $do_store;
        }
    }
}

