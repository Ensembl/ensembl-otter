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

add_havana_xrefs.pl - adds xrefs to Havana genes for external annotation

=head1 SYNOPSIS

add_havana_xrefs.pl [options]

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
    --prune                             reset to the state before running this
                                        script
=head1 DESCRIPTION

This script adds xrefs to Havana genes for external annotation - the former is 
updated whereas the latter is frozen.


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);
use Storable;

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::SeqIO::genbank;
use Data::Dumper;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'chromosomes|chr=s@',
  'gene_stable_id|gsi=s@',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
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


# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa = $dba->get_SliceAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $ea = $dba->get_DBEntryAdaptor();


# delete all existing Havana xrefs if --prune option is used

if ($support->param('prune') and $support->user_proceed('Would you really like to delete all previously generated Havana xrefs before running this script?')) {
  my $num;
  # xrefs
  $support->log("Deleting all Havana xrefs...\n");
  $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name = 'Havana_gene';
        ));
  $support->log("Done deleting $num entries.\n");

  # object_xrefs
  $support->log("Deleting orphan object_xrefs...\n");
  $num = $dba->dbc->do(qq(
           DELETE ox
           FROM object_xref ox
           LEFT JOIN xref x ON ox.xref_id = x.xref_id
           WHERE x.xref_id IS NULL
        ));
  $support->log("Done deleting $num entries.\n");
}

my @gene_stable_ids = $support->param('gene_stable_id');
my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);

my ($total_found,$total_not_found,$total_external) = (0,0,0);

# loop over chromosomes
$support->log("Looping over chromosomes: @chr_sorted\n\n");
foreach my $chr (@chr_sorted) {
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");

  # fetch genes from db
  $support->log("Fetching genes...\n");
  my $slice = $sa->fetch_by_region('chromosome', $chr);
  my $genes = $slice->get_all_Genes();
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");

  my $havana_genes;
  my ($havana_c,$external_c,$found,$not_found) = (0,0,0,0);
  $support->log("Analysing Havana genes...\n");
  foreach my $gene (@{$genes}) {
    my $analysis_name = $gene->analysis->logic_name;
    next unless ($analysis_name eq 'otter');
    $havana_c++;
    my $gsi = $gene->stable_id;
    my $gene_name = $gene->display_xref->display_id;
    # filter to user-specified gene_stable_ids
    if (scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }
    #add display_xref name
    if ($havana_genes->{$gene_name} ) {
      $support->log_warning("Name $gene_name attached to genes $gsi and ".$havana_genes->{$gene_name}."\n");
    }
    else {
      $havana_genes->{$gene_name} = $gsi;
    }
  }

  # loop over genes again and store xrefs to Havana ones for external genes
  $support->log("\nAnalysing External genes...\n");
  foreach my $gene (@$genes) {
    my $analysis_name = $gene->analysis->logic_name;
    next if ($analysis_name eq 'otter');
    $external_c++;

    my $gene_name = $gene->display_xref->display_id;
    my $gid = $gene->dbID;
    my $gsi = $gene->stable_id;
    # filter to user-specified gene_stable_ids
    if (scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }
    my ($stripped_name,$prefix);	
    # see if the gene_name has a prefix
    ($prefix,$stripped_name) = $gene_name  =~ /(.*?):(.*)/;
    unless ($stripped_name) {
      $stripped_name = $prefix;
      $prefix = 0;
    }

    $support->log_verbose("Checking gene $gene_name ($gid, $gsi) using $stripped_name...\n",1);
    #store xref if there is one
    if (my $pid = $havana_genes->{$stripped_name} ) {
      $support->log("Gene $gene_name ($gsi) matches Havana gene $stripped_name ($pid).\n",1);
      $found++;
      #check if it's there already...
      my ($existing_xref,$dbID);		
      if ($existing_xref = $ea->fetch_by_db_accession('Havana_gene',$pid)) {
	$support->log_verbose("Using previous xref for gene $gsi (Havana_gene display_id $pid).\n", 1);
	$gene->add_DBEntry($existing_xref);
	$dbID = $ea->store($existing_xref, $gid, 'gene',1) unless $support->param('dry_run');
      } else {
	my $dbentry = Bio::EnsEMBL::DBEntry->new(
	  -primary_id => $pid,
	  -display_id => $pid,
	  -version    => 1,
	  -release    => 1,
	  -dbname     => 'Havana_gene',
	  -status     => 'XREF',
	);
	$gene->add_DBEntry($dbentry);
	if ($support->param('dry_run')) {
	  $support->log_verbose("Would store xref ($pid) for gene $gene_name ($gsi, $gid)\n", 1);
	}
	else {
	  $dbID = $ea->store($dbentry, $gid, 'gene',1) unless $support->param('dry_run');
	  if ($dbID) {
	    $support->log_verbose("Stored xref: display_id $pid (dbID $dbID) for gene $gene_name ($gsi, $gid)\n", 1);
	  }
	  else {
	    $support->log_warning("Problem storing xref ($pid) for gene $gene_name ($gsi, $gid)\n");
	  }
	}
      }
    }
    else {
      $support->log_verbose("No match found for gene $gene_name ($gsi, $gid)\n", 1); 
      $not_found++;
    }
  }

  # log stats
  $support->log("\nFound $havana_c havana genes and $external_c external genes (of ".scalar @$genes." on this chromosome).\n");
  $support->log("External genes with a match = $found, without = $not_found\n");
  $support->log_stamped("Done with chromosome $chr.\n\n");

  $total_found += $found;
  $total_not_found += $not_found;
  $total_external += $external_c
}

#create a summary
$support->log("\nOf $total_external external genes, $total_found have a match to a Havana gene and $total_not_found do not\n");

# finish log
$support->finish_log;
