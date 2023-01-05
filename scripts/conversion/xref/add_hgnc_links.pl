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


=head1 NAME

add_hgnc_links.pl

=head1 SYNOPSIS

add_hgnc_links.pl [options]

General options:

    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)

    --dbname, db_name=NAME              use database NAME
    --host, --dbhost, --db_host=HOST    use database host HOST
    --port, --dbport, --db_port=PORT    use database port PORT
    --user, --dbuser, --db_user=USER    use database username USER
    --pass, --dbpass, --db_pass=PASS    use database passwort PASS
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive                   run script interactively (default: true)
    -n, --dry_run, --dry                don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

    -hgncfixfile=FILE                   read HGNC details from file (optional, to download is default)

=head1 DESCRIPTION

Downloads a file from HGNC (or reuses an existing one) and adds xrefs for any new HGNC names. Reports on differences in
(i) stable IDs used by HGNC that are not in Vega
(ii) names of protein coding genes that are out of sync between us and HGNC - send to anacode for fixing (hgnc_names_to_fix.txt).
(iii) Where the name mismatch is accompanied by a biotype difference (ie where HGNC think the stable ID is not
protein coding genes then these are reported seperately (hgnc_links_to_review.txt)


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use FindBin qw($Bin);
use vars qw( $SERVERROOT );

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift @INC,"$SERVERROOT/bioperl-live";
  unshift @INC,"$SERVERROOT/ensembl/modules";
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use POSIX qw(strftime);
use LWP::UserAgent;
use Storable;
use Data::Dumper;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
$support->parse_common_options(@_);
$support->parse_extra_options(
  'hgncfixfile=s',
  'anacode_file=s',
  'jel_file=s',
  'elsepth_file=s',
  'prune');
$support->allowed_params(
  $support->get_common_params,
  'hgncfixfile',
  'anacode_file',
  'jel_file',
  'elspeth_file',
  'prune');

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

my $date = strftime "%Y-%m-%d", localtime;
$support->param('anacode_file',($support->param('logpath')."/hgnc_names_to_fix_${date}.txt"))       unless $support->param('anacode_file');
$support->param('jel_file',    ($support->param('logpath')."/hgnc_biotypes_to_review_${date}.txt")) unless $support->param('jel_file');
$support->param('elspeth_file',($support->param('logpath')."/hgnc_names_to_review_${date}.txt"))    unless $support->param('elspeth_file');

$support->confirm_params;
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $ga = $dba->get_GeneAdaptor;
my $ea  = $dba->get_DBEntryAdaptor();

my $anacode_fh = $support->filehandle('>', $support->param('anacode_file'));
my $jel_fh     = $support->filehandle('>', $support->param('jel_file'));
my $elspeth_fh = $support->filehandle('>', $support->param('elspeth_file'));

#get info from HGNC
my $records;
my $xref_file = $support->param('logpath').$support->param('dbname')."-hgnc_update-parsed_records.file";
if (-e $xref_file) {
  if ($support->user_proceed("Read xref records from a previously saved files - $xref_file ?\n")) {
    $records = retrieve($xref_file);
  }
  #or parse..
  else {
    $support->log_stamped("Reading xref input files...\n");
    $records = &parse_hgnc;
    store($records,$xref_file);
  }
}
else {
  $support->log_stamped("Reading xref input files...\n");
  $records = &parse_hgnc;
  store($records,$xref_file);
}
#warn Dumper($records);

#create backup first time around
my %tables;
my $dbname = $support->param('dbname');
map { $_ =~ s/`//g;  $_ =~ s/$dbname.//g; $tables{$_} += 1; } $dbh->tables;
if (! exists($tables{'backup_uhgncl_xref'}) ) {
  $dbh->do(qq(CREATE table backup_uhgncl_xref select * from xref));
  $dbh->do(qq(CREATE table backup_uhgncl_object_xref select * from object_xref));
}

#prune
if ($support->param('prune') and $support->user_proceed('Would you really like to delete changes from previous runs of this script ?')) {
  $dbh->do(qq(DELETE FROM xref));
  $dbh->do(qq(DELETE FROM object_xref));
  $dbh->do(qq(INSERT INTO xref SELECT * FROM backup_uhgncl_xref));
  $dbh->do(qq(INSERT INTO object_xref SELECT * FROM backup_uhgncl_object_xref));
}

my (@potential_names_script_2,@potential_names_script,@potential_biotype_mismatches,@ignored_new_names,@hgnc_errors_easy,@hgnc_errors_hard);
my $add_c = 0;
foreach my $gsi (keys %$records) {
  my $gene = $ga->fetch_by_stable_id($gsi);
  my $hgnc_rec = $records->{$gsi}[0];
  my $hgnc_name = $hgnc_rec->{'hgnc_symbol'};
  my $hgnc_biotype = $hgnc_rec->{'type'};

  #warn where a gene in the HGNC record is not in Vega
  if (!$gene) {
    my $pot_hgnc_matches;
     foreach my $pot_g (@{$ga->fetch_all_by_display_label($hgnc_name)}) {
       my $other_gsi = $pot_g->stable_id;
       my $slice = $pot_g->slice;
       my $sr = $slice->seq_region_name;
       if ($sr !~ /19-/) {
         $pot_hgnc_matches .= "$other_gsi ";
       }
     }
    if ($pot_hgnc_matches) {
      $support->log("Gene $gsi is not in Vega, but based on name ($hgnc_name), Vega suggests using $pot_hgnc_matches\n");
      push @hgnc_errors_easy, [$gsi,$hgnc_biotype,$hgnc_name,$pot_hgnc_matches];
    }
    else {
      $support->log("Gene $gsi is not in Vega, no suggestions ie the name ($hgnc_name) doesn't exist in Vega\n");
      push @hgnc_errors_easy, [$gsi,$hgnc_biotype,$hgnc_name];
    }
    next;
  }
  my $display_name = $gene->display_xref->display_id;
  my $disp_xref_dbname = $gene->display_xref->dbname;
  my @vega_genes = @{$ga->fetch_all_by_display_label($display_name)};
  my @hgnc_genes = @{$ga->fetch_all_by_display_label($hgnc_name)};

  #warn if something's gone wrong (when adding HGNC xrefs earlier?)
  if ($display_name eq $hgnc_name) {
    if ($disp_xref_dbname ne 'HGNC') {
      $support->log_warning("Gene $gsi has an HGNC name but not an HGNC xref - you should update HGNC xrefs if they were done a while ago\n");
    }
    next;
  }
  else {
    #do Vega and HGNC have a different genes with the same name
    if (scalar(@hgnc_genes) > 1) {
      foreach my $g (@hgnc_genes) {
        my $other_gsi = $g->stable_id;
        next if ($other_gsi eq $gsi);
        my $slice = $g->slice;
        my $sr = $slice->seq_region_name;
        if ($slice->is_reference()) {
          $support->log("Vega gene $other_gsi has the same name ($hgnc_name) that HGNC has attached to $gsi\n");
        }
      }
    }
  }

  $support->log_verbose("Gene $gsi ($display_name) has a name at HGNC ($hgnc_name), need to add an xref\n");
  my ($existing_xref,$dbID);
  my $hgnc_pid = $hgnc_rec->{'hgnc_pid'};

  #if there is an existing xref use it, if not create a new one
  my $gid = $gene->dbID;
  my $dbID;
  my $existing_xref = $ea->fetch_by_db_accession('HGNC',$hgnc_pid);
  if ($existing_xref && $existing_xref->display_id eq $hgnc_name) {
    my $old_dbID = $existing_xref->dbID;
    $support->log_verbose("Using previous xref ($old_dbID) for gene $display_name ($gsi).\n", 3);
    $gene->add_DBEntry($existing_xref);
    if (! $support->param('dry_run')) {
      $dbID = $ea->store($existing_xref, $gid, 'gene');
    }
  }
  else {
    $support->log_verbose("Creating new HGNC xref for gene $display_name ($gsi).\n", 3);
    my $dbentry = Bio::EnsEMBL::DBEntry->new(
      -primary_id => $hgnc_pid,
      -display_id => $hgnc_name,
      -version    => 1,
      -dbname     => 'HGNC',
#      -description => $hgnc_rec->{'description'}, #could add description here if we wished to
    );
    $gene->add_DBEntry($dbentry);
    if (! $support->param('dry_run')) {
      $dbID = $ea->store($dbentry, $gid, 'gene', 1);
    }
  }
  #was the store succesfull ?
  if ($dbID) {
    $add_c++;
    $support->log("Stored HGNC xref (display_id = $hgnc_name, pid = $hgnc_pid) for gene $display_name ($gsi)\n", 2);
  }
  elsif (! $support->param('dry_run')) {
    $support->log_warning("Failed to store HGNC xref for gene $display_name ($gsi)\n");
  }

  my $desc    = $hgnc_rec->{'description'};
  my $biotype = $gene->biotype;
  my $sr      = $gene->seq_region_name;

  #log non protein coding genes but only report verbosely
  if ($biotype ne 'protein_coding') {
    push @ignored_new_names, [$gsi,$display_name,$hgnc_name,$desc,$biotype,$sr];
  }
  else {
    if ( $hgnc_rec->{'type'} eq 'gene with protein product') {
      my $manual = 1;
      if (    ($display_name =~ /^C[XY\d]{1,2}orf/)
           || ($display_name =~ /^A[BCFLP]\d+\.\d{1,2}$/)
           || ($display_name =~ /^RP\d{1,2}-/) ) {
        $support->log_verbose("Consider this name ($hgnc_name) for an automatic name update\n",1);
        $manual = 0;
        push @potential_names_script, [$gsi,$biotype,$sr,$display_name,$hgnc_name,$desc];
      }
      else {
        $support->log_verbose("Consider this name ($hgnc_name) for an update\n",1);
        push @potential_names_script_2, [$gsi,$biotype,$sr,$display_name,$hgnc_name,$desc];
      }

      #look for other genes that share the same name and are on non-reference slices, ie should have their names updated as well
      if (scalar(@vega_genes) > 1) {
        foreach my $g (@vega_genes) {
          my $other_gsi = $g->stable_id;
          next if $other_gsi eq $gsi;
          my $slice = $g->slice;
          my $sr = $slice->seq_region_name;
          if ($slice->is_reference()) {
            $support->log_warning("Gene $gsi shares a name ($display_name) with $other_gsi, but the latter is on region $sr, a reference slice\n");
          }
          else {
            $support->log_verbose("Consider this other gene ($other_gsi on $sr) for an update to $hgnc_name\n",1);
            my $rec = [$other_gsi,$biotype,$sr,$display_name,$hgnc_name,$desc];
            if ($manual) {
              push @potential_names_script_2,$rec;
            }
            else {
              push @potential_names_script,$rec;
            }
          }
        }
      }
    }
    else {
      $support->log_verbose("Biotype mismatch as well as name mismatch between Vega and HGNC ($hgnc_biotype) for $gsi ($hgnc_name)\n",1);
      push @potential_biotype_mismatches, [$gsi,$biotype,$hgnc_biotype,$sr,$display_name,$hgnc_name,$desc];
    }
  }
}
$support->log("\nAdded $add_c HGNC xrefs\n");

$support->log("\nSummary:\n-------\n");
my $c = scalar(@ignored_new_names);
if ($support->param('verbose')) {
  $support->log("\nNames to ignore:\n\n");
  $support->log(sprintf("%-30s%-20s%-20s\n", qw(STABLE_ID OLD_NAME NEW_NAME)));
  foreach my $rec (@ignored_new_names) {
    $support->log(sprintf("%-30s%-20s%-20s%-20s\n", $rec->[0], $rec->[1], $rec->[2]));
  }
}
else {
  $support->log("\nThere are $c ignored names (because the Vega gene is not protein_coding), to see these rerun in verbose mode\n\n");
}

$c = scalar(@potential_biotype_mismatches);
$support->log("\nBiotype mismatches to consider ($c):\n\n");
$support->log(sprintf("%-25s%-25s%-25s%-20s%-20s%-20s%-20s\n", qw(STABLE_ID VEGA_BIOTYPE HGNC_BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC)));
print $jel_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\t%s\n", qw(STABLE_ID VEGA_BIOTYPE HGNC_BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC));
foreach my $rec (sort { $a->[3] <=> $b->[3] } @potential_biotype_mismatches) {
  $support->log(sprintf("%-25s%-25s%-25s%-20s%-20s%-20s%-20s\n", $rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4], $rec->[5], $rec->[6]));
  print $jel_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\t%s\n",$rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4], $rec->[5], $rec->[6]);
}

$c = scalar(@potential_names_script);
$support->log("\nClone based names to update by script ($c):\n\n");
$support->log(sprintf("%-25s%-30s%-20s%-20s%-20s%-20s\n", qw(STABLE_ID VEGA_BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC)));
print $anacode_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\n", qw(STABLE_ID VEGA_BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC));
print $anacode_fh sprintf("\n#Clone based names to update by script\n");
foreach my $rec (sort { $a->[2] <=> $b->[2] } @potential_names_script) {
  $support->log(sprintf("%-25s%-30s%-20s%-20s%-20s%-20s\n", $rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4], $rec->[5]));
  print $anacode_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\n", $rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4], $rec->[5]);
}

$c = scalar(@potential_names_script_2);
$support->log("\nOther names to update by script ($c):\n\n");
$support->log(sprintf("%-25s%-30s%-20s%-20s%-20s%-20s\n", qw(STABLE_ID VEGA_BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC)));
print $anacode_fh sprintf("\n#Other names to update by script\n");
foreach my $rec (sort { $a->[2] <=> $b->[2] } @potential_names_script_2) {
  $support->log(sprintf("%-25s%-30s%-20s%-20s%-20s%-20s\n", $rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4], $rec->[5]));
  print $anacode_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\n",$rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4], $rec->[5]);
}

$c = scalar(@hgnc_errors_easy);
$support->log("\nVega stable IDs in HGNC but not in Vega that should be easy to update ($c):\n\n");
$support->log(sprintf("%-25s%-30s%-20s%-20s\n", qw(STABLE_ID BIOTYPE NAME POSSIBLES)));
print $elspeth_fh sprintf("\n#HGNC Stable IDs to rename\n");
foreach my $rec (sort { $a->[2] <=> $b->[2] } @hgnc_errors_easy) {
  $support->log(sprintf("%-25s%-30s%-20s%-20s\n", $rec->[0], $rec->[1], $rec->[2], $rec->[3]));
  print $elspeth_fh sprintf("%s\t%s\t%s\t%s\n",$rec->[0], $rec->[1], $rec->[2], $rec->[3]);
}

$c = scalar(@hgnc_errors_hard);
$support->log("\nVega stable IDs in HGNC ut not in Vega that will be harder to update ($c):\n\n");
$support->log(sprintf("%-25s%-30s%-20s%-20s\n", qw(STABLE_ID BIOTYPE NAME)));
print $elspeth_fh sprintf("\n#HGNC Stable IDs to work out how rename\n");
foreach my $rec (sort { $a->[2] <=> $b->[2] } @hgnc_errors_hard) {
  $support->log(sprintf("%-25s%-30s%-20s\n", $rec->[0], $rec->[1], $rec->[2]));
  print $elspeth_fh sprintf("%s\t%s\t%s\n",$rec->[0], $rec->[1], $rec->[2]);
}

$support->finish_log;

sub parse_hgnc {
  my $records;

  #try and download direct
  $support->log_stamped("Parsing HGNC for links and descriptions...\n", 1);
  my $url = "http://www.genenames.org/cgi-bin/hgnc_downloads?col=gd_hgnc_id&col=gd_app_sym&col=gd_app_name&col=gd_locus_type&col=gd_vega_ids&status=Approved&status_opt=2&where=&order_by=gd_hgnc_id&format=text&limit=&hgnc_dbtag=on&submit=submit";

  my $ua = LWP::UserAgent->new;
  $ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');
  my $resp = $ua->get($url);
  my $page = $resp->content;
  if ($page) {
    $support->log("File downloaded from HGNC\n",1);
  }
  else {
    # otherwise read input file from HGNC
    $support->log("Unable to download from HGNC, trying to read from disc: ".$support->param('hgncfixfile')."\n",1);
    open (NOM, '<', $support->param('hgncfixfile')) or $support->throw(
      "Couldn't open ".$support->param('hgncfixfile')." for reading: $!\n");
    $page = do { local $/; <NOM> };
  }
  my @recs = split "\n", $page;

  #define which columns to parse out of the record
  my %wanted_columns = (
    'HGNC ID'         => 'hgnc_pid',
    'Approved Symbol' => 'hgnc_symbol',
    'Approved Name'   => 'description',
    'Locus Type'      => 'type',
    'Vega ID'         => 'vega_id',
  );

  # read header (containing column titles) and check all wanted columns are there
  my $line = shift @recs;
  chomp $line;
  my @columns =  split /\t/, $line;
  foreach my $wanted (keys %wanted_columns) {
    unless (grep { $_ eq $wanted} @columns ) {
      $support->log_error("Can't find $wanted column in HGNC record\n");
    }
  }

  #make a note of positions of wanted fields
  my $status_column;
  my %fieldnames;
  for (my $i=0; $i < scalar(@columns); $i++) {
    my $column_label =  $columns[$i];
    next if (! $wanted_columns{$column_label});
    $fieldnames{$i} = $wanted_columns{$column_label};
  }

  #retrieve each column and save against Vega ID
  foreach my $rec (@recs) {
    chomp $rec;
    my @fields = split /\t/, $rec, -1;
    my $entry = {};
    my $id;
    foreach my $i (keys %fieldnames) {
      my $type = $fieldnames{$i};
      $id =  $fields[$i] if $type eq 'vega_id';
      $entry->{$type} = $fields[$i];
    }
    if ($id) {
      push @{$records->{$id}}, $entry;
    }
  }

  #check each ID only has one record
  foreach my $id (keys %$records) {
    if (scalar @{$records->{$id}} > 1) {
      $support->log_warning("Vega gene ID in HGNC record more than once, not using it since needs sorting on their part\n");
      delete $records->{$id};
    }
  }

  return $records;
}


