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


=head1 NAME

add_vega_xrefs.pl - add xrefs to display gene, transcript and translation names

=head1 SYNOPSIS

add_vega_xrefs.pl [options]

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
    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gene_stable_id, --gsi=LIST|FILE   only process LIST gene_stable_ids
                                        (or read list from FILE)
    --gene_type=TYPE                    only process genes of type TYPE
    --prune                             delete all xrefs (except Interpro) and
                                        gene/transcript.display_xref_ids before
                                        running the script

=head1 DESCRIPTION

This script retrieves annotated gene/transcript names and adds them as xrefs
to genes/transcripts/translations, respectively, setting them as display_xrefs.


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>
Patrick Meidl <meidl@ebi.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

### PARALLEL # $support ###

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'chromosomes|chr=s@',
  'gene_stable_id|gsi=s@',
  'gene_type=s',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
  'gene_type',
  'prune',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->list_or_file('gene_stable_id');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors (caching features on one slice only)
my $dba = $support->get_database('ensembl');
my $sa = $dba->get_SliceAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $ea = $dba->get_DBEntryAdaptor();

# statement handles for display_xref_id updates
my $sth_gene  = $dba->dbc->prepare("update gene set display_xref_id=? where gene_id=?");
my $sth_trans = $dba->dbc->prepare("update transcript set display_xref_id=? where transcript_id=?");

my (@chr_sorted,@gene_stable_ids,$chr_length);
### PRE # @gene_stable_ids $chr_length # ###

# delete all xrefs if --prune option is used
if ($support->param('prune') and $support->user_proceed('Would you really like to delete all vega and external xrefs  before running this script?')) {

  my $num;
  # xrefs
  $support->log("Deleting all vega and external xrefs...\n");
  $num = $dba->dbc->do(qq(
        DELETE x
        FROM xref x, external_db ed
        WHERE x.external_db_id = ed.external_db_id
        AND ed.db_name != 'Interpro'
    ));
  $support->log("Done deleting $num entries.\n");

  # object_xrefs
  $support->log("Deleting all object_xrefs...\n");
  $num = $dba->dbc->do(qq(
        DELETE ox
          FROM object_xref ox
     LEFT JOIN xref x ON ox.xref_id = x.xref_id
         WHERE x.xref_id IS NULL));
  $support->log("Done deleting $num entries.\n");

  # gene.display_xref_id
  $support->log("Resetting gene.display_xref_id...\n");
  $num = $dba->dbc->do(qq(UPDATE gene set display_xref_id = 0));
  $support->log("Done resetting $num genes.\n");

  # transcript.display_xref_id
  $support->log("Resetting transcript.display_xref_id...\n");
  $num = $dba->dbc->do(qq(UPDATE transcript set display_xref_id = 0));
  $support->log("Done resetting $num transcripts.\n");
}

@gene_stable_ids = $support->param('gene_stable_id');
$chr_length = $support->get_chrlength($dba,'','',1);
@chr_sorted = $support->sort_chromosomes($chr_length);
my $chrs = \@chr_sorted;

$support->log("Looping over chromosomes: @chr_sorted\n\n");

### SIZE # (\d+|X|Y)+ # 1 ###
### SIZE # # 0.25 ###
### RUN # $chrs ###

my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;

# loop over chromosomes
foreach my $chr (@$chrs) {
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");
  # fetch genes from db
  $support->log("Fetching genes...\n");
  my $slice = $sa->fetch_by_region('toplevel', $chr);
  my $genes = $slice->get_all_Genes;
  $support->log("Done fetching ".scalar @$genes." genes.\n\n");

  # loop over genes
  my ($gnum, $tnum, $tlnum);
 GENE:
  foreach my $gene (@$genes) {
    my $gsi = $gene->stable_id;
    my $gid = $gene->dbID;

    # filter to user-specified gene_stable_ids
    if (scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }

    #get (unique) name from gene attrib, or use stable ID
    my $gene_name = &get_name($gene);
    next GENE unless ($gene_name);

    $support->log_verbose("Gene $gene_name ($gid, $gsi)...\n");
	
    # filter to user-specified gene_type
    my $gene_type = $support->param('gene_type');
    if ($gene_type and ($gene_type ne $gene->type)){
      $support->log_verbose("Skipping gene - not of type $gene_type.\n", 1);
      next;
    }
		
    # add the gene name as an xref to db
    $gnum++;
    my $dbentry = Bio::EnsEMBL::DBEntry->new(
      -primary_id => $gene->stable_id,
      -display_id => $gene_name, 
      -version    => 1,
      -release    => 1,
      -dbname     => "Vega_gene",
    );
    $dbentry->status('KNOWN');
    $gene->add_DBEntry($dbentry);
    if (! $support->param('dry_run')) {
      my $dbID = $ea->store($dbentry, $gid, 'Gene',1);
      $sth_gene->execute($dbID, $gid);
      $support->log_verbose("Stored xref $dbID for gene $gsi ($gid).\n", 1);
    }
		
    # loop over transcripts
  TRANS:
    foreach my $trans (@{$gene->get_all_Transcripts}){
      my $tid = $trans->dbID;
      my $tsi = $trans->stable_id;
      my $trans_name = &get_name($trans);
      next TRANS unless ($trans_name);

      $support->log_verbose("Transcript $trans_name ($tid, $tsi)...\n", 1);
			
      # add transcript name as an xref to db
      $tnum++;
      my $dbentry = Bio::EnsEMBL::DBEntry->new(
	-primary_id=>$trans->stable_id,
	-display_id=>$trans_name, 
	-version=>1,
	-release=>1,
	-dbname=>"Vega_transcript",
      );
      $dbentry->status('KNOWN');
      if (! $support->param('dry_run')) {
	my $dbID = $ea->store($dbentry, $tid, 'Transcript',1);
	$sth_trans->execute($dbID, $tid);
	$support->log_verbose("Stored xref $dbID for transcript $tsi ($tid).\n", 2);
      }
			
      # translations
      my $translation = $trans->translation;
      if ($translation) {
	# add translation name as xref to db
	$tlnum++;
	my $tlsi = $translation->stable_id;
	my $tlid =  $translation->dbID;
	my $dbentry = Bio::EnsEMBL::DBEntry->new(
	  -primary_id=>$tlid,
	  -display_id=>$tlid, 
	  -version=>1,
	  -release=>1,
	  -dbname=>"Vega_translation",
	);
	$dbentry->status('KNOWN');
	if (! $support->param('dry_run')) {
	  $ea->store($dbentry, $trans->translation->dbID, 'Translation',1);
	  $support->log_verbose("Stored xref ".$dbentry->dbID." for translation $tlsi ($tlid).\n", 2);
	}
      }
    }
  }
	
  $support->log("\nAdded xrefs for $gnum (of ".scalar @$genes.") genes, $tnum transcripts, $tlnum translations.\n");
  $support->log_stamped("Done with chromosome $chr.\n\n");
}

### POST ###

# finish log
$support->finish_log;

### END ###

sub get_name {
  my $obj = shift;
  my $sid = $obj->stable_id;
  my $id  = $obj->dbID;
  my $type = ($obj->isa("Bio::EnsEMBL::Gene"))       ? 'Gene'
    : ($obj->isa("Bio::EnsEMBL::Transcript")) ? 'Transcript'
      : undef;
  if (! $type) {
    $support->log_warning("Don't know how to deal with an object of type ",ref($obj),". Skipping\n");
    return undef;
  }
  my $name;
  my @names = map {$_->value} @{$obj->get_all_Attributes('name')};
  if (! @names ) {
    $support->log_warning("$type $id ($sid) has no name attrib, using stable ID.\n");
    $name = $sid;
  }
  elsif (scalar (@names > 1)) {
    my %unique_names;
    map {$unique_names{$_}++} @names;
    if (scalar(keys %unique_names) > 1 ) {
      $support->log_warning("$type $id ($sid) has multiple different name attribs, using stable ID.\n");
      $name = $sid;
    }
    else {
      $name = $names[0];
    }	
  }
  else {
    $name =  $names[0];
  }
  return $name;
}
	
