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


=head1 NAME

add_ebi_xrefs.pl - adds go and Uniprot xrefs to translations

=head1 SYNOPSIS

add_external_xrefs.pl [options]

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

    --gene_stable_id                    limit to stable IDs only
    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gofile=FILE                       read GO input file
    --prune                             reset to the state before running this
                                        script

=head1 DESCRIPTION

This script parses a GOA input file to add GO and Uniprot xrefs to Vega translations

Data comes from a file provided by Tony Sawford (tonys@ebi.ac.uk) from GOA:

ftp://ftp.ebi.ac.uk/pub/contrib/goa/vega2goa.gz



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
#use Bio::SeqIO::genbank;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
### PARALLEL # $support ###

# priorites from GOA
my %evidence_priorities = (
  IDA => '1',   # inferred from direct assay
  IMP => '2',   # inferred from mutant phenotype
  IGI => '3',   # inferred from genetic interaction
  IPI => '4',   # inferred from physical interaction
  IEP => '5',   # inferred from expression pattern
  EXP => '6',   # inferred from experiment
  ISO => '7',   # inferred from sequence orthology
  ISA => '7',   # inferred from sequence alignment
  ISS => '8',   # inferred from sequence or structural similarity
  IBD => '8',   # Inferred from Biological aspect of Descendant
  IKR => '8',   # Inferred from Key Residues
  IRD => '8',   # Inferred from Rapid Divergence
  IBA => '8',   # Inferred from Biological aspect of Ancestor
  ISM => '8',   # Inferred from sequence model
  IGC => '9',   # Inferred from Genomic Context
  NAS => '10',  # non-traceable author statement
  TAS => '11',  # traceable author statement
  IC  => '12',   # inferred by curator
  RCA => '13',  # reviewed computational annotation
  IEA => '14', # inferred from electronic annotation
  ND  => '15',  # no data
);


# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'chromosomes|chr=s@',
  'gene_stable_id|gsi=s@',
  'ebifile=s',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
  'ebifile',
  'prune',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->list_or_file('gene_stable_id');

$support->check_required_params('ebifile');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa  = $dba->get_SliceAdaptor();
my $ga  = $dba->get_GeneAdaptor();
my $tla = $dba->get_TranslationAdaptor();
my $ea  = $dba->get_DBEntryAdaptor();

my ($chr_length,$overall_c,$parsed_xrefs);
$parsed_xrefs = {};
### PRE # $chr_length $parsed_xrefs # $overall_c ###

# delete previous xrefs if --prune option is used
if ($support->param('prune') and $support->user_proceed("Would you really like to delete xrefs from previous runs of this script?")) {

  my $external_dbtypes = join("', '", qw(Uniprot/SWISSPROT Quick_Go_Evidence Quick_Go GO));

  $support->log("Deleting xrefs...\n");
  my $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name in ('$external_dbtypes')));
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

  # ontology_xrefs
  $support->log("Deleting ontology_xrefs...\n");
  $num = $dba->dbc->do(qq(DELETE FROM ontology_xref));
  $support->log("Done deleting $num entries.\n");
}

my %gene_stable_ids = map { $_, 1 }  $support->param('gene_stable_id');
my $xref_file    = $support->param('logpath').'/'.$support->param('dbname')."-EBI-parsed_records.file";

# read input files... either retrieve from disc
if (-e $xref_file) {
  if ($support->user_proceed("Read xref records from a previously saved files - $xref_file ?\n")) {
    $parsed_xrefs = retrieve($xref_file);
  }
}

#or parse and store to disc...
if (! %$parsed_xrefs ) {
  $support->log_stamped("Reading xref input files...\n");
  &parse_go;
  $support->log_stamped("Finished parsing xrefs, storing to file...\n");
  store($parsed_xrefs,$xref_file);
}

if ($support->param('verbose')) {
  $support->log("Parsed xrefs are ".Dumper($parsed_xrefs)."\n");
#  exit;
}

$support->log_stamped("Done.\n\n");

$chr_length = $support->get_chrlength($dba,'','chromosome',1); #will retrieve non-reference slices
my @chr_sorted = $support->sort_chromosomes($chr_length);

### RUN # @chr_sorted ###

$overall_c = 0;

# fetch genes from db
$support->log("Fetching genes...\n");
foreach my $chr (@chr_sorted) {
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");
  my $slice = $sa->fetch_by_region('toplevel', $chr);
  my ($genes) = $support->get_unique_genes($slice,'',1);
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");
  my $chr_c = 0;
 GENE:
  foreach my $gene (@{$genes}) {
    my $gsi = $gene->stable_id;	

    # filter to user-specified gene_stable_ids
    if (scalar(keys(%gene_stable_ids))){
      next GENE unless $gene_stable_ids{$gsi};
    }

    my $gene_name = $gene->display_xref->display_id;
    $support->log_verbose("Studying $gene_name ($gsi)...\n",1);

  TRANS:
    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      if (my $trl = $trans->translation() ) {
        my $tsi   = $trans->stable_id;
	my $trlsi = $trl->stable_id;
	my $trlid = $trl->dbID;

        unless ($parsed_xrefs->{$trlsi}) {
          $support->log_verbose("No match found for $trlsi.\n",2);
          next TRANS;
        }

        unless ( $parsed_xrefs->{$trlsi}{'Uniprot/SWISSPROT'} && $parsed_xrefs->{$trlsi}{'GO'}) {
          $support->log_error("Parsed file not in the correct format, please check\n");
        }

        $chr_c++;
        $overall_c++;

        #uniprot is easy, just add an xref to the translation
        my ($uniprot_pid,$uniprot_rec) = %{$parsed_xrefs->{$trlsi}{'Uniprot/SWISSPROT'}};
        $support->log_verbose("Creating new Uniprot xref for $trlsi $uniprot_pid.\n", 2);
        my $dbentry = Bio::EnsEMBL::DBEntry->new(
          -primary_id => $uniprot_pid,
          -display_id => $uniprot_rec->{'display_label'},
          -version    => 1,
          -info_type  => 'DEPENDENT',
          -dbname     => 'Uniprot/SWISSPROT',
        );
        $trl->add_DBEntry($dbentry);
        if (! $support->param('dry_run')) {
          if (my $dbID = $ea->store($dbentry, $trlid, 'translation', 1)) {
            $support->log_verbose("Stored Uniprot xref (display_id = $uniprot_pid, dbID = $dbID) for $trlsi\n", 3);
          }
          else {
            $support->log_warning("Failed to store Uniprot xref for $trlsi\n");
          }
        }

        #go requires an ontology xref and an xref (for Annotation source)
        while ( my ($go_pid,$go_rec) = each %{$parsed_xrefs->{$trlsi}{'GO'}}) {
          my $ev_type = $go_rec->{'ev_code'};
          unless ($ev_type) {
            $support->log_warning("No evidence type associated with $go_pid ($trlsi), please check input file\n");
            $ev_type = '';
          }

          #add link to GOA
          $support->log_verbose("Creating new Quick_GO xref for $trlsi $go_pid.\n", 2);
          $dbentry = Bio::EnsEMBL::DBEntry->new(
            -primary_id => $go_rec->{'uniprot_acc'},
            -display_id => $go_rec->{'uniprot_acc'},
            -version    => 1,
            -info_type  => 'DEPENDENT',
            -dbname     => 'Quick_Go',
          );
          $trl->add_DBEntry($dbentry);
          if (! $support->param('dry_run')) {
            if (my $dbID = $ea->store($dbentry, $trlid, 'translation', 1)) {
              $support->log_verbose("Stored Quick_GO xref (display_id = $go_pid, dbID = $dbID, source_db = ".$go_rec->{'assigned_by'}." for $trlsi\n", 3);
            }
            else {
              $support->log_warning("Failed to store Quick_GO xref for $trlsi\n");
            }
          }

          #add GO xrefs
          $support->log_verbose("Creating new GO xref for $trlsi $go_pid.\n", 2);
          $dbentry = Bio::EnsEMBL::OntologyXref->new(
            -primary_id  => $go_pid,
            -display_id  => $go_rec->{'display_label'},
            -version     => 1,
            -info_type   => 'DEPENDENT',
            -dbname      => 'GO',
            -description => $go_rec->{'go_name'},
          );

          my $source_xref = Bio::EnsEMBL::DBEntry->new(
            -primary_id  => $go_rec->{'uniprot_acc'},
            -display_id  => $go_rec->{'assigned_by'},
            -info_type   => 'DEPENDENT',
            -dbname      => 'Quick_Go_Evidence',
            -version => 1,
            -info_text   => 'Quick_Go:'.$go_rec->{'assigned_by'},
          );
          $dbentry->add_linkage_type($ev_type,$source_xref);
          $trl->add_DBEntry($dbentry);
          if (! $support->param('dry_run')) {
            if (my $dbID = $ea->store($dbentry, $trlid, 'translation', 1)) {
              $support->log_verbose("Stored GO xref (display_id = $go_pid, dbID = $dbID, source_db = ".$go_rec->{'assigned_by'}." for $trlsi\n", 3);
            }
            else {
              $support->log_warning("Failed to store GO xref for $trlsi\n");
            }
          }
        }
      }
    }
  }
  if ($support->param('dry_run')) {
    $support->log("$chr_c GO xrefs wold have been added for chromosome $chr\n");
  }
  else {
    $support->log("$chr_c GO xrefs added for chromosome $chr\n");
  }
}

### POST ###

$support->log("$overall_c GO xrefs found in total\n");

### END ###

$support->finish_log;


=head2 parse_go

=cut

sub parse_go {
  $support->log_stamped("Reading EBI file...\n", 1);
  # read input file from GO
  open (EBI, '<', $support->param('ebifile')) or $support->throw(
    "Couldn't open ".$support->param('ebifile')." for reading: $!\n");
  my %source_dbs;
  my $prev_tlsi;
  my $rec;
  while (<EBI>) {
    next if $_ =~ /^#/;
    my @fields = split /\t/, $_;
    my $tlsi         = $fields[0]; # add GO and Uniprot xrefs to this *translation*
#    next unless $tlsi eq 'OTTHUMP00000080295';

    my $uniprot      = $fields[1]; # used for Uniprot xrefs and for links to Quick GO for 'Annotation source'
    my $go_id        = $fields[2]; # self explanatory [= xref.display_label and xref.dbprimary_acc]
    my $go_name      = $fields[4]; # ie description of the GO term [= xref.description]
    my $ev_code      = $fields[5]; # type of evidence, eg IEA [= ontology_xref.linkage]# 
    my $assigned_by  = $fields[8]; # who made the connection, ie 'Annotation source' (also used for link to QuickGO

    unless ($evidence_priorities{$ev_code}) {
      $support->log_error("evidence code '$ev_code' is not in our priority list, contact EBI to find out where it should lie\n");
    }

    chomp $assigned_by;
    $source_dbs{$assigned_by}++;

#    my $go_aspect    = $fields[3]; # F(unction), P(rocess) or C(omponent) (not used)
#    my $ref          = $fields[6]; # identifier of the source cited as the authority for attributing a GO term to a gene product (not used)
#    my ($extra_db,$extra_acc) = split ':', $fields[7]; # extra evidence that supports the annotation - used as 'annotation source' by e! code but inaccurately

    #sanity checks
    chomp $go_id;
    if ( ($tlsi !~ /^OTT[A-Z]{3}P/) || ( $go_id !~ /^GO:/) ) {
      $support->log_error("Check format of input file ($tlsi -- $go_id)\n");
    }

    #go back and remove any redundant records
    if ($prev_tlsi && ($tlsi ne $prev_tlsi)) {
      &cleanup_and_store($rec,$prev_tlsi);
      $rec = {};
    }

    $rec->{$tlsi}{'Uniprot/SWISSPROT'}{$uniprot} = {
      'pid'           => $uniprot,
      'display_label' => $uniprot,
    };
    push @{$rec->{$tlsi}{'GO'}{$go_id}}, {
        'pid'           => $go_id,
        'display_label' => $go_id,
        'go_name'       => $go_name,
        'ev_code'       => $ev_code,
        'assigned_by'   => $assigned_by,
        'uniprot_acc'   => $uniprot,
      };

    $prev_tlsi  = $tlsi;
  }

  &cleanup_and_store($rec,$prev_tlsi);
  $support->log_verbose("Sources of annotation are ".Dumper(\%source_dbs)."\n",1);
}

#select just one of the GO records (by evidence code priority) and then add to $parsed_xrefs
sub cleanup_and_store {
  my ($rec,$tlsi) = @_;

  #select just one record after ordering by priority
  my $wanted_rec;
  while ( my ($go_id,$go_rec) = each (%{$rec->{$tlsi}{'GO'}}) ) {
    if (scalar(@$go_rec) > 1) {
      my @sorted = sort { $evidence_priorities{$a->{'ev_code'}} <=> $evidence_priorities{$b->{'ev_code'}} } @$go_rec;
      $wanted_rec = shift @sorted;
    }
    else {
      $wanted_rec = shift @$go_rec;
    }
    $rec->{$tlsi}{'GO'}{$go_id} = $wanted_rec;
  }
  $parsed_xrefs->{$tlsi} = $rec->{$tlsi};
}

#http://www.ebi.ac.uk/QuickGO/GAnnotation?source=ZFIN&protein=Q90X37&db=ZFIN
