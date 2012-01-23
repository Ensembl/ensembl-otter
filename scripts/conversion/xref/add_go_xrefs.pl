#!/usr/bin/env perl

=head1 NAME

add_go_xrefs.pl - adds go xrefs to translations

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

This script parses GO input file to add xrefs to Vega translations

Data comes from a file provided by Matthias Haimel (mhaimel@ebi.ac.uk) from IPI

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
  'gofile=s',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
  'gofile',
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
my $sa  = $dba->get_SliceAdaptor();
my $ga  = $dba->get_GeneAdaptor();
my $tla = $dba->get_TranslationAdaptor();
my $ea  = $dba->get_DBEntryAdaptor();

# delete previous GO xrefs if --prune option is used
if ($support->param('prune') and $support->user_proceed('Would you really like to delete xrefs from previous runs of this script that have used these options?')) {

  $support->log("Deleting  external xrefs...\n");

  my $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name = 'GO'));
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

  # go_xrefs
  $support->log("Deleting go_xrefs...\n");
  $num = $dba->dbc->do(qq(
           DELETE FROM go_xref
        ));
  $support->log("Done deleting $num entries.\n");
}

my %gene_stable_ids = map { $_, 1 }  $support->param('gene_stable_id');
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);

my $parsed_xrefs = {};
my $xref_file    = $SERVERROOT.'/'.$support->param('dbname')."-GO-parsed_records.file";

# read input files... either retrieve from disc
if (-e $xref_file) {
  if ($support->user_proceed("Read xref records from a previously saved files - $xref_file ?\n")) {
    $parsed_xrefs = retrieve($xref_file);
  }
  #or parse..
  else {
    $support->log_stamped("Reading xref input files...\n");
    &parse_go($parsed_xrefs);
    $support->log_stamped("Finished parsing xrefs, storing to file...\n");
    store($parsed_xrefs,$xref_file);
  }
}
		
#or parse.
else {
  $support->log_stamped("Reading xref input files...\n");
  &parse_go($parsed_xrefs);
	
  $support->log_stamped("Finished parsing xrefs, storing to file...\n");
  store($parsed_xrefs,$xref_file);
}

if ($support->param('verbose')) {
  $support->log("Parsed xrefs are ".Dumper($parsed_xrefs)."\n");
}

$support->log_stamped("Done.\n\n");

# loop over chromosomes
$support->log("Looping over chromosomes: @chr_sorted\n\n");
my $overall_c = 0;

foreach my $chr (@chr_sorted) {
  my $chr_c = 0;
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");

  # fetch genes from db
  $support->log("Fetching genes...\n");
  my $slice = $sa->fetch_by_region('toplevel', $chr);
  my $genes = $ga->fetch_all_by_Slice($slice);
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");

  my $gnum = 0;
 GENE:
  foreach my $gene (@$genes) {
    my $gsi = $gene->stable_id;	
    # filter to user-specified gene_stable_ids
    if (scalar(keys(%gene_stable_ids))){
      next GENE unless $gene_stable_ids{$gsi};
    }

    my $gene_name = $gene->display_xref->display_id;
    $support->log_verbose("Studying $gene_name ($gsi)...\n");
    $gnum++;

    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      if (my $trl = $trans->translation() ) {
	my $trlsi = $trl->stable_id;
	my $trlid = $trl->dbID;
	
	$support->log_verbose("Searching for name $trlsi...\n",1);
	if (my $links = $parsed_xrefs->{$trlsi}) {
	  $support->log_verbose("Match found for $trlsi.\n",1);

	MATCH:
	  foreach my $match (@{$links->{'GO'}}) {
	    $chr_c++;
	    $overall_c++;
	    my ($xid,$ev_type) = split /\|\|/, $match;

	    unless ($xid) {
	      $support->log_warning("Parsed file not in the correct format, please check\n");
	      next MATCH;
	    }
	    $ev_type ||= 'NULL';
	    $support->log_verbose("Creating new GO xref for $trlsi--$match.\n", 3);
	    my $dbentry = Bio::EnsEMBL::OntologyXref->new(
	      -primary_id => $xid,
	      -display_id => $xid,
	      -version    => 1,
	      -info_type  => 'DEPENDENT',
	      -dbname     => 'GO',
	    );
	    $dbentry->add_linkage_type($ev_type);

	    $trl->add_DBEntry($dbentry);
	    if (! $support->param('dry_run')) {
	      if (my $dbID = $ea->store($dbentry, $trlid, 'translation', 1)) {
		$support->log_verbose("Stored GO xref (display_id = $xid, evidence = $ev_type) for $trlsi\n", 3);
	      }
	      else {
		$support->log_warning("Failed to store GO xref for $trlsi\n");
	      }
	    }
	  }
	}								
	else {
	  $support->log_verbose("No match found for $trlsi.\n",1);					
	}
      }
    }
  }
  $support->log("$chr_c GO xrefs added for chromosome $chr\n");
}

$support->log("$overall_c GO xrefs found\n");

$support->finish_log;


=head2 parse_go

=cut

sub parse_go {
  my ($xrefs, $lcmap) = @_;
  $support->log_stamped("GO...\n", 1);
  # read input file from GO
  open (GO, '<', $support->param('gofile')) or $support->throw(
    "Couldn't open ".$support->param('gofile')." for reading: $!\n");
  while (<GO>) {
    my @fields = split /\t/, $_;
    #skip non VEGA records
    next if $fields[0] =~ /^#/;
    my $tlsi = $fields[0];
    my $xid  = $fields[1];
    chomp $xid;
    my ($ev_type) = $fields[2] =~ /^([A-Z]*):/;

    #sanity checks
    if ( ($tlsi !~ /^OTT[A-Z]{3}P/) || ( $xid !~ /^GO:/) ) {
      $support->log_warning("Check format of input file ($tlsi -- $xid)\n");
    }
    else {
      push @{$xrefs->{$tlsi}->{'GO'}} , $xid.'||'.$ev_type;
    }
  }
}
