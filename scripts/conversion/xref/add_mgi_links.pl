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

update_mgi_links.pl

=head1 SYNOPSIS

update_mgi_links.pl [options]

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

    -mgi_file=FILE                      read MGI description from file

=head1 DESCRIPTION

Parses a file from MGI and adds xrefs for any new MGI names. Reports on names
that we don't use so these can be sent back to Havana. Checks if old names are also
attached to genes on non-reference slices (ie DIL regions)

File to use is ftp://ftp.informatics.jax.org/pub/reports/MRK_VEGA.rpt - it'll be donwloaded by
the script.


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
use LWP::UserAgent;
use POSIX qw(strftime);
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Data::Dumper;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
$support->parse_common_options(@_);
$support->parse_extra_options(
  'mgifixfile=s',
  'jel_file=s',
  'prune');
$support->allowed_params(
  $support->get_common_params,
  'mgifixfile',
  'jel_file',
  'prune');
if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}
$support->confirm_params;
$support->init_log;

my $date = strftime "%Y-%m-%d", localtime;
$support->param('jel_file', ($support->param('logpath')."/mgi_names_to_fix_${date}.txt")) unless $support->param('jel_file');
my $jel_fh     = $support->filehandle('>', $support->param('jel_file'));

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa = $dba->get_SliceAdaptor;
my $ga = $dba->get_GeneAdaptor;
my $ea  = $dba->get_DBEntryAdaptor();

#get info from MGI file
my $records = &parse_mgi;
#warn Dumper($records);

#get chr details
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);

#create backup first time around
my %tables;
my $dbname = $support->param('dbname');
map { $_ =~ s/`//g;  $_ =~ s/$dbname.//g; $tables{$_} += 1; } $dbh->tables;
if (! exists($tables{'backup_aml_xref'}) ) {
  $dbh->do(qq(CREATE table backup_aml_xref select * from xref));
  $dbh->do(qq(CREATE table backup_aml_object_xref select * from object_xref));
}

#prune
if ($support->param('prune') and $support->user_proceed('Would you really like to delete changes from previous runs of this script ?')) {
  $dbh->do(qq(DELETE FROM xref));
  $dbh->do(qq(DELETE FROM object_xref));
  $dbh->do(qq(INSERT INTO xref SELECT * FROM backup_aml_xref));
  $dbh->do(qq(INSERT INTO object_xref SELECT * FROM backup_aml_object_xref));
}

my (@potential_names,@ignored_new_names);
my $add_c = 0;
foreach my $chr (@chr_sorted) {
  next if ($chr =~ /idd/);
  $support->log_stamped("\n> Chromosome $chr (".$chr_length->{$chr}."bp).\n");

  # fetch genes from db
  my $slice = $sa->fetch_by_region('toplevel', $chr);
  my $genes = $slice->get_all_Genes();
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");
 GENE:
  foreach my $gene (@{$genes}) {
    next if ($gene->analysis->logic_name !~ /otter|otter_external/); #ignore EUCOMM genes
    my $display_name;
    my $gsi = $gene->stable_id;
    my $gid = $gene->dbID;
    my $biotype = $gene->biotype;

    eval { $display_name = $gene->display_xref->display_id};
    if ($@) {
      $support->log_warning ("Can't get xref for gene $gsi on chr $chr, skipping\n");
      next GENE;
    }
    my $disp_xref_dbname = $gene->display_xref->dbname;
    next if ($disp_xref_dbname eq 'MGI'); #go no further with MGI genes since they already have MGI xrefs!

    $support->log_verbose("Looking at gene $gsi - $display_name (current source = $disp_xref_dbname):\n");

    foreach my $rec (@{$records->{$gsi}}) {
      my $new_mgi_name = $rec->{'symbol'};
      if ($new_mgi_name eq $display_name) {
        $support->log_warning("The name downloaded from MGI matches the name in Vega ($new_mgi_name) but the gene ($gsi) doesn't have an MGI display_xref. Please re-add the MGI xrefs\n",1);
      }

      $support->log_verbose("Gene $gsi ($display_name) has a name at MGI ($new_mgi_name), need to add an xref\n");
      my ($existing_xref,$dbID);
      my $mgi_pid = $rec->{'mgi_pid'};

      #if there is an existing MGI xref use it, if not create a new one
      $existing_xref = $ea->fetch_by_db_accession('MGI',$mgi_pid);
      if ($existing_xref && $existing_xref->display_id eq $new_mgi_name) {
        my $old_dbID = $existing_xref->dbID;
        $support->log_verbose("Using previous MGI xref ($old_dbID) for gene $display_name ($gsi).\n", 3);
        $gene->add_DBEntry($existing_xref);
        if (! $support->param('dry_run')) {
          $dbID = $ea->store($existing_xref, $gid, 'gene');
        }
      }
      else {
        $support->log_verbose("Creating new MGI xref for gene $display_name ($gsi).\n", 3);
        my $dbentry = Bio::EnsEMBL::DBEntry->new(
          -primary_id => $mgi_pid,
          -display_id => $new_mgi_name,
          -version    => 1,
          -dbname     => 'MGI',
#          -description => $rec->{'desc'}, #could add MGI description here if we wished to
        );
        $gene->add_DBEntry($dbentry);
        if (! $support->param('dry_run')) {
          $dbID = $ea->store($dbentry, $gid, 'gene', 1);
        }
      }
      #was the store succesfull ?
      if ($dbID) {
        $add_c++;
        $support->log("Stored MGI xref (display_id = $new_mgi_name, pid = $mgi_pid) for gene $display_name ($gsi)\n", 2);
      }
      elsif (! $support->param('dry_run')) {
        $support->log_warning("Failed to store MGI xref for gene $display_name ($gsi)\n");
      }

      #for passing on to havana as potential names first exclude many styles of names
      if (  ($new_mgi_name =~ /[A-Z]{2}|Gm/)
         || ($new_mgi_name =~ /Rik\d{0,1}$/)
         || ($new_mgi_name =~ /^D\d{1,2}[A-Z]/)
         || ($new_mgi_name =~ /^D[X|Y][A-Z]\d{6}/)
         || ($new_mgi_name =~ /^[A-Z]\d{5}/) ) {
        push @ignored_new_names, [$gsi,$display_name,$new_mgi_name,$biotype,$chr];
        $support->log_verbose("Ignoring $new_mgi_name since wrong format\n",1);
      }
      else {
        my $desc    = $rec->{'desc'};
        $support->log_verbose("Consider this name ($new_mgi_name) for an update\n",1);
        push @potential_names, [$gsi,$display_name,$new_mgi_name,$desc,$biotype,$chr];

        #look for other genes that share the same name and are on non-reference slices, ie should have their names updated as well
        my @genes = @{$ga->fetch_all_by_display_label($display_name)};
        if (scalar(@genes) > 1) {
          foreach my $g (@genes) {
            my $other_gsi = $g->stable_id;
            next if $other_gsi eq $gsi;
            my $slice = $g->slice;
            my $sr = $slice->seq_region_name;
            if ($slice->is_reference()) {
              $support->log_warning("Gene $other_gsi shares a name ($display_name) but is on region $sr, a reference slice\n");
            }
            else {
              $support->log_verbose("Consider this other gene ($other_gsi on $sr) for an update to $new_mgi_name\n",1);
              push @potential_names, [$other_gsi,$display_name,$new_mgi_name,$desc,$biotype,$sr];
            }
          }
        }
      }
    }
  }
}

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
  $support->log("\nThere are $c ignored names, to see these rerun in verbose mode\n\n");
}

$c = scalar(@potential_names);
$support->log("\nNames to consider)($c):\n\n");
$support->log(sprintf("%-25s%-30s%-20s%-20s%-20s%-20s\n", qw(STABLE_ID BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC)));
print $jel_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\n", qw(STABLE_ID BIOTYPE SEQ_REGION OLD_NAME NEW_NAME NEW_DESC));
foreach my $rec (@potential_names) {
  $support->log(sprintf("%-25s%-30s%-20s%-20s%-20s%-20s\n", $rec->[0], $rec->[4], $rec->[5], $rec->[1], $rec->[2], $rec->[3]));
  print $jel_fh sprintf("%s\t%s\t%s\t%s\t%s\t%s\n",$rec->[0], $rec->[4], $rec->[5], $rec->[1], $rec->[2], $rec->[3]);
}

$support->log("\nAdded $add_c MGI xrefs\n");

$support->finish_log;

sub parse_mgi {
  my $records;

  #try and download direct
  my $ua = LWP::UserAgent->new;
  $ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');
  my $url = 'ftp://ftp.informatics.jax.org/pub/reports/MRK_VEGA.rpt';
  my $resp = $ua->get($url);
  my $page = $resp->content;
  if ($page) {
    $support->log("$url downloaded from MGI\n",1);
  } else {
    if($support->param('nolocal')) {
      $support->log_error("Couldn't retrieve file and --nolocal given");
    }
    my $mgifile = $support->param('mgifixfile');
    open(MGI, "< $mgifile")
      or $support->throw("Couldn't open $mgifile for reading: $!\n");
    my $page = do { local $/; <MGI> };
    close MGI;
  }
  my @recs = split "\n", $page;

  #parse input
  foreach my $rec (@recs) {
    my (@fields) = split /\t/, $rec;
    my $mgi_pid = $fields[0];
    my $symbol  = $fields[1];
    my $desc    = $fields[2];
    my $ottid   = $fields[5]; 

    push @{$records->{$ottid}},{ symbol  => $symbol,
                                 mgi_pid => $mgi_pid,
                                 desc    => $desc,
                               };
  }
  return $records;
}


