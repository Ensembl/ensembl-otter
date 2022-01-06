#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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


use warnings;


#!/usr/bin/env perl

use warnings;


use strict;
use Getopt::Long 'GetOptions';
use Bio::Otter::Lace::Defaults;
use Storable;


my $del_sptr_mapping    = "del_sp_tr_acc_mapping";
my $primary_acc_db      = "acc_2_sp_tr_mapping";
my $sec_2_prim_acc      = "sec_2_prim_acc_mapping";

my $D_SW_TR             = {}; # obsolete accs of Sw/Tr
my $primary_2_acc_db    = {}; # primary acc to Sw: or Tr:
my $secondary_2_primary = {}; # secondary acc to primary acc

{
  my ($dataset, $prepare, $download);
  my $help = sub { exec('perldoc', $0) };

  Bio::Otter::Lace::Defaults::do_getopt(
      'ds|dataset=s' => \$dataset,    # eg, human or mouse or zebrafish
      'h|help'       => $help,
      'download'     => \$download,
      'prepare'      => \$prepare,
      ) or $help->();                  # plus default options
  $help->() unless ( $dataset );

  my $client      = Bio::Otter::Lace::Defaults::make_Client();          # Bio::Otter::Lace::Client
  my $dset        = $client->get_DataSet_by_name($dataset);             # Bio::Otter::Lace::DataSet
  my $otter_db    = $dset->get_cached_DBAdaptor;                        # Bio::EnsEMBL::Containerr

  my $ftp = "ftp://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/";
  my $sp_del = "docs/delac_sp.txt";
  my $tr_del = "docs/delac_tr.txt";

  my $type = 0;

  if ( $download ){
    foreach my $file (  $sp_del, $tr_del ){
      my $f = $ftp.$file;

      # downloading list of deleted SW and TREM acc
      my $c = system("wget $f");
      die if $c != 0;
      $type++;
      $file =~ s/docs\/// if $file =~ /docs/;

      get_fasta_headers_only($D_SW_TR, $del_sptr_mapping, $file, $type );
    }
  }

  prepare_uniprot_data(connect_uniprot_db("uniprot_8_4")) if $prepare;

  # read back data
  $D_SW_TR             = retrieve($del_sptr_mapping);
  $primary_2_acc_db    = retrieve($primary_acc_db);
  $secondary_2_primary = retrieve($sec_2_prim_acc);

  # to be on the safe side, don't want to just patch directy to otter
  # so keep the SQL in an external file as a record
  make_sqls_to_patch_otter_evidences($otter_db, $dataset);
}

sub get_fasta_headers_only {
  my ($D_SW_TR, $del_sptr_mapping, $download, $type ) = @_;

  foreach (`cat $download`){
    chomp;
    if ( /^([O,P,Q][0-9][A-Z,0-9][A-Z,0-9][A-Z,0-9][0-9])/ ){
      $D_SW_TR->{$1} = "Sw:" if $type == 1;
      $D_SW_TR->{$1} = "Tr:" if $type == 2;
    }
  }
  store($D_SW_TR, $del_sptr_mapping);

  return;
}

sub connect_uniprot_db {

  my $dbname = shift;

  my $dbh = DBI->connect("DBI:mysql:$dbname:193.62.52.185:3310", "genero", "", {RaiseError => 1})
        || die "cannot connect to $dbname, $DBI::errstr";
  return $dbh;
}

sub prepare_uniprot_data {

  my $dbh = shift;

  # separate primary and secondary acc in 2 queries runs way faster than when not
  # in uniprot_8_4
  #| qualifier | count(*) |
  #+-----------+----------+
  #| primary   |  3281787 |
  #| secondary |   141612 |
  #+-----------+----------+

  my $primary = $dbh->prepare(qq{
    SELECT a.accession, e.data_class
    FROM accession a, entry e
    WHERE a.entry_id = e.entry_id
    AND a.qualifier ='primary'
    }
      );

  $primary->execute;
  while ( my ($acc, $sw_tr) = $primary->fetchrow ) {
    $primary_2_acc_db->{$acc} = $sw_tr;
  }
  $primary->finish;

  my $secondary = $dbh->prepare("SELECT entry_id FROM accession where qualifier = 'secondary'");
  $secondary->execute;

  my @entry_ids;
  while( my $entry_id = $secondary->fetchrow ){
    push(@entry_ids, $entry_id);
  }
  $secondary->finish;

  my $qry = $dbh->prepare(qq{
    SELECT a.accession, a.qualifier, e.data_class
    FROM accession a, entry e
    WHERE a.entry_id = e.entry_id
    AND a.entry_id = ?
    ORDER BY a.qualifier;
    }
      );

  foreach my $id ( @entry_ids ) {
    $qry->execute($id);

    my $prim_acc;
    while ( my ($acc, $prim_sec, $sw_tr) = $qry->fetchrow ) {
      if ( $prim_sec eq "primary" ){
        $prim_acc = $acc;
      }
      $secondary_2_primary->{$acc} = $prim_acc if $prim_sec eq "secondary";
    }
  }

  # prepare hash in disk for use later
  store($primary_2_acc_db, $primary_acc_db);
  store($secondary_2_primary, $sec_2_prim_acc);

  return;
}


sub make_sqls_to_patch_otter_evidences {

  my ($dbh, $ds) = @_;

  my $evis = $dbh->prepare(qq{
    SELECT evidence_name
    FROM evidence
    WHERE evidence_name
    NOT REGEXP "^..:"
    }
      );
  $evis->execute;

  my $sql;
  while ( my $acc = $evis->fetchrow ){
    my $ori_acc = $acc;
    $acc =~ s/\.\d+$//;

    if ( my $prefix = $primary_2_acc_db->{$acc} ){

      # uniprot primary acc
      $prefix eq "STD" ? ($prefix = "Sw:") : ($prefix = "Tr:");
      my $new_name = $prefix.$acc;
      $sql .= qq{update evidence set evidence_name = '$new_name' where evidence_name = '$acc'}. "\n";

    }
    elsif ( exists $D_SW_TR->{$acc} ){
      print "#$acc OBSOLETE\n";
    }
    elsif ( my $primAcc = $secondary_2_primary->{$acc} ){

      # dealing with uniprot secondary acc
      my $prefix = $primary_2_acc_db->{$primAcc};
    
      $prefix eq "STD" ? ($prefix = "Sw:") : ($prefix = "Tr:");
      print "#$acc is secondary to $primAcc [$prefix]\n";
      my $new_name = $prefix.$acc; # not changed to primary acc, only append Sw: or Tr:
    
      $sql .= qq{update evidence set evidence_name = '$new_name' where evidence_name = '$acc'}. "\n";

    }
    elsif ( $acc =~ /^[O,P,Q]/ and $acc !~ /_/) {
      print "#$acc NOT FOUND\n";
    }
    elsif ( $acc =~ /^N[C,G,T,Z,M,R,P]_|^X[M,R,P]_|^ZP_/ ) {
      # current NCBI RefSeq records: NC_, NG_, NT_, NZ_, NM_, NR_, XM_, XR_, NP_, XP_, ZP_
      print "#REFSEQ: $acc\n";
    }
    elsif ( $acc =~ /^[A-Z0-9]{1,5}_[A-Z]{1,5}/ ){
      # SW entry_name, eg 5NTD_MOUSE
      print "#SW_ENTRY_NAME $acc\n";
    }
    elsif ( $acc =~ /^[O,P,Q].+_[A-Z0-9]{1,5}/ ){
      # "virtual" codes have been defined that regroup organisms at a certain taxonomic level.
      # Such codes are prefixed by the number "9" and generally correspond to a "pool" of organisms
      # eg, 9BACT

      # TR entry_name, eg P71025_BACSU
      print "#TR_ENTRY_NAME $acc\n";
    }
    else {
      # all the rest goes to Em:
      my $new_name = "Em:$acc";
      $sql .= qq{update evidence set evidence_name = '$new_name' where evidence_name = '$ori_acc'}. "\n";
    }
  }
  print $sql;

  return;
}



