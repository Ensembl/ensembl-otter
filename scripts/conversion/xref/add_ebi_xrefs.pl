#!/usr/bin/env perl

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


=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

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
#  unshift(@INC, "$SERVERROOT/bioperl-live");
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
  'ebifile=s',
  'xrefformat=s',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
  'ebifile',
  'xrefformat',
  'prune',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->list_or_file('gene_stable_id');

$support->check_required_params('ebifile','xrefformat');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

my $xrefformat = $support->param('xrefformat');
if ($xrefformat !~ /Uniprot\/SWISSPROT|GO/) {
  $support->log_error("Please set xrefformat option to 'Uniprot/SWISSPROT' or 'GO'\n");
}

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa  = $dba->get_SliceAdaptor();
my $ga  = $dba->get_GeneAdaptor();
my $tla = $dba->get_TranslationAdaptor();
my $ea  = $dba->get_DBEntryAdaptor();


# delete previous xrefs if --prune option is used
if ($support->param('prune') and $support->user_proceed("Would you really like to delete $xrefformat xrefs from previous runs of this script?")) {

  $support->log("Deleting $xrefformat xrefs...\n");

  my $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name = '$xrefformat'));
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
  
  if ($xrefformat eq 'GO') {

    #GOA Evidence xrefs
    $support->log("Deleting GO source object_xrefs...\n");
    my $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db edb
           WHERE x.external_db_id = edb.external_db_id
           AND edb.db_name = 'Quick_Go_Evidence'));
    $support->log("Done deleting $num entries.\n");

    #GOA xrefs
    $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db edb
           WHERE x.external_db_id = edb.external_db_id
           AND edb.db_name = 'Quick_Go'));
    $support->log("Done deleting $num entries.\n");

    # ontology_xrefs
    $support->log("Deleting ontology_xrefs...\n");
    $num = $dba->dbc->do(qq(DELETE FROM ontology_xref));
    $support->log("Done deleting $num entries.\n");
  }
}

my %gene_stable_ids = map { $_, 1 }  $support->param('gene_stable_id');
my $parsed_xrefs = {};
my $xref_file    = $SERVERROOT.'/'.$support->param('dbname')."-EBI-parsed_records.file";

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

my $overall_c = 0;
my $chr_length = $support->get_chrlength($dba,'','chromosome',1); #will retrieve non-reference slices
my @chr_sorted = $support->sort_chromosomes($chr_length);

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
    $support->log_verbose("Studying $gene_name ($gsi)...\n");

    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      if (my $trl = $trans->translation() ) {
        my $tsi   = $trans->stable_id;
	my $trlsi = $trl->stable_id;
	my $trlid = $trl->dbID;
	my ($pid,$rec);
	while ( ($pid,$rec) = each (%{$parsed_xrefs->{$trlsi}{$xrefformat}})) {
	  $support->log_verbose("Match found for $tsi.\n",1);
          unless ($rec->{'pid'}) {
            $support->log_warning("Parsed file not in the correct format, please check\n");
          }
          $chr_c++;
          $overall_c++;

          my $dbentry;

          if ($xrefformat eq 'Uniprot/SWISSPROT') {
            #uniprot is easy, just add an xref to the tranlsation
            $support->log_verbose("Creating new $xrefformat xref for $trlsi $pid.\n", 2);
            $dbentry = Bio::EnsEMBL::DBEntry->new(
              -primary_id => $pid,
              -display_id => $rec->{'display_label'},
              -version    => 1,
              -info_type  => 'DEPENDENT',
              -dbname     => $xrefformat,
            );
          }
          else {
            #go requires an ontology xref and an xref (for Annotation source)
            my $ev_type = $rec->{'ev_code'};
            unless ($ev_type) {
              $support->log_warning("No evidence type associated with $pid ($trlsi), please check input file\n");
              $ev_type = '';
            }

            #add link to GOA
            $dbentry = Bio::EnsEMBL::DBEntry->new(
              -primary_id => $rec->{'uniprot_acc'},
              -display_id => $rec->{'uniprot_acc'},
              -version    => 1,
              -info_type  => 'DEPENDENT',
              -dbname     => 'Quick_Go',
            );
            $trl->add_DBEntry($dbentry);
            if (! $support->param('dry_run')) {
              if (my $dbID = $ea->store($dbentry, $trlid, 'translation', 1)) {
                $support->log_verbose("Stored Quick_GO xref (display_id = $pid, dbID = $dbID, source_db = ".$rec->{'assigned_by'}." for $trlsi\n", 3);
              }
              else {
                $support->log_warning("Failed to store Quick_GO xref for $trlsi\n");
              }
            }

            #add GO xrefs
            $support->log_verbose("Creating new $xrefformat xref for $trlsi $pid.\n", 2);
            $dbentry = Bio::EnsEMBL::OntologyXref->new(
              -primary_id  => $pid,
              -display_id  => $rec->{'display_label'},
              -version     => 1,
              -info_type   => 'DEPENDENT',
              -dbname      => $xrefformat,
              -description => $rec->{'go_name'},
            );

            my $source_xref = Bio::EnsEMBL::DBEntry->new(
              -primary_id  => $rec->{'uniprot_acc'},
              -display_id  => $rec->{'assigned_by'},
              -info_type   => 'DEPENDENT',
              -dbname      => 'Quick_Go_Evidence',
              -version => 1,
              -info_text   => 'Quick_Go:'.$rec->{'assigned_by'},
            );
            $dbentry->add_linkage_type($ev_type,$source_xref);

            ##what's significance of info_type ?

          }

          $trl->add_DBEntry($dbentry);
          if (! $support->param('dry_run')) {
            if (my $dbID = $ea->store($dbentry, $trlid, 'translation', 1)) {
              $support->log_verbose("Stored $xrefformat xref (display_id = $pid, dbID = $dbID, source_db = ".$rec->{'assigned_by'}." for $trlsi\n", 3);
            }
            else {
              $support->log_warning("Failed to store GO xref for $trlsi\n");
            }
          }
        }								
        if (! $pid) {
          $support->log_verbose("No match found for $trlsi.\n",1);					
        }
      }
    }
  }
  $support->log("$chr_c $xrefformat xrefs added for chromosome $chr\n");
}

$support->log("$overall_c $xrefformat xrefs found in total\n");

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

#    if (! $rec->{$tlsi}{'uniprot'}{$uniprot}) {
#      push @{$rec->{$tlsi}{'uniprot'}{$uniprot}}, {
#        'pid'           => $uniprot,
#        'display_label' => $uniprot,
#      };
#    }
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
    IGC => '9',   # Inferred from Genomic Context
    NAS => '10',  # non-traceable author statement
    TAS => '11',  # traceable author statement
    IC => '12',   # inferred by curator
    RCA => '13',  # reviewed computational annotation
    IEA  => '14', # inferred from electronic annotation
    ND  => '15',  # no data
  );

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
