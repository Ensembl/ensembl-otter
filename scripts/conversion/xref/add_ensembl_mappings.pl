#!/usr/bin/env perl

=head1 NAME

add_ensembl_mappings.pl - adds xrefs to ensembl transcripts/genes

=head1 SYNOPSIS

add_ensembl_mappings.pl [options]

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
    --prune                             reset to the state before running this
                                        script
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive                   run script interactively (default: true)
    -n, --dry_run, --dry                don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

    --ensemblhost=HOST                  use Ensembl database host HOST
    --ensemblport=PORT                  use Ensembl database port PORT
    --ensembluser=USER                  use Ensembl database username USER
    --ensemblpass=PASS                  use Ensembl database password PASS

    --db_type                           if set to 'ensembl-vega' updates ensembl vega database
    --evegadbname                       NAME, HOST, PORT, USER, PASS used
    --evegahost                           instead of the main database
    --evegaport                           params if db_type set to
    --evegauser                           ensembl-vega, otherwise ignored.
    --evegapass

    --assembly                          used to identify target chromosomes
    --alt_assembly                      used instead of assembly iff
                                          db_type is set to ensembl-vega


=head1 DESCRIPTION

This script extracts xrefs from an ensembl database that link VEGA and Havana genes and transcripts.

Script will warn where a particular pair of objects are linked with more than one external_db type.

Other warnings indicate where a Vega transcript used in Ensembl is no longer present in Vega,
and other problems such as failure to store an xref in the db for whatever reason.

It will report where Vega genes / transcripts don't have e! xrefs (excludes TEC / artifact)

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

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Data::Dumper;
use Storable;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(qw(
    chromosomes|chr=s@ prune assembly=s alt_assembly=s db_type=s
    ensemblhost=s ensemblport=s ensembluser=s ensemblpass=s ensembldbname=s
    evegadbname=s evegahost=s evegaport=s evegauser=s evegapass=s
  )
);
$support->allowed_params(
  $support->get_common_params,qw(
    chromosomes prune assembly alt_assembly db_type
    ensemblhost ensemblport ensembluser ensemblpass ensembldbname
    evegadbname evegahost evegaport evegauser evegapass
  )
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect databases and get adaptors
#ensembl db
my $dba;
my $assembly;
if($support->param('db_type') eq 'ensembl-vega') {
  $dba = $support->get_database('ensembl','evega');
  # don't set dnadb as then sa will use it including eg get_chrlength!
  $assembly = $support->param('alt_assembly');
} else {
  $dba = $support->get_database('ensembl');
  $assembly = $support->param('assembly');
}
my $dbh = $dba->dbc->db_handle;
my $ta = $dba->get_TranscriptAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $ea = $dba->get_DBEntryAdaptor();
my $sa = $dba->get_SliceAdaptor();

my $edba = $support->get_database('ensembl','ensembl');
my $esa  = $edba->get_SliceAdaptor();

# delete all ensembl xrefs if --prune option is used
if (!$support->param('dry_run')) {
  if ($support->param('prune') and $support->user_proceed("Would you really like to delete all previously added ENS xrefs before running this script?")) {
    my $num;
    # xrefs
    $support->log("Deleting all ensembl_id xrefs...\n");
    $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name like \'ENS%\'
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
}
elsif ($support->param('prune')){
  $support->log("Not deleting any xrefs since this is a dry run.\n");
}
	
#links xrefs and the biotypes they link to (reported just for info)
my (%assigned_txrefs, %assigned_gxrefs) = ({},{});

#retrieve mappings from disc or parse database
my $ens_ids = {};
my $xref_file    = $support->param('logpath').'/'.$support->param('ensembldbname')."-ensembl-mappings.file";
if (-e $xref_file) {
  if ($support->user_proceed("Read xref records from a previously saved file ?\n")) {
    $ens_ids = retrieve($xref_file);
  }
}

if (! %$ens_ids) {
 CHR:
  foreach my $slice (@{$esa->fetch_all('chromosome',undef,1)}) {
    my $chr_name = $slice->seq_region_name;
    next CHR if ($chr_name =~ /^NT|MT/);
    $support->log("Retrieving Ensembl genes from chromosome $chr_name...\n");
  GENE:
    foreach my $g (@{$slice->get_all_Genes()}) {
      next GENE unless ($g->analysis->logic_name =~ /havana/);
      my $gsi = $g->stable_id;
    GXREF:
      foreach my $x (@{$g->get_all_DBEntries}){
	my $dbname = $x->dbname;
	my $vname = $x->primary_id;
	next GXREF unless ($x->type =~ /ALT/);
	next GXREF unless ($vname =~ /OTT/);
	$assigned_gxrefs{$dbname}->{$g->biotype}++;
	$ens_ids->{'genes'}{$vname}{$gsi}{$dbname}++;
      }
      foreach my $t (@{$g->get_all_Transcripts}) {
	my $tsi = $t->stable_id;
	unless ($tsi) { $support->log_error("No stable ID found for transcript ".$t->dbID."\n"); }
      TXREF:
	foreach my $x (@{$t->get_all_DBEntries}){
	  my $dbname = $x->dbname;
	  my $vname = $x->primary_id;
	  next TXREF unless ($x->type =~ /ALT/);
	  next TXREF unless ($vname =~ /OTT/);
	  $assigned_txrefs{$dbname}->{$t->biotype}++;
	  $ens_ids->{'transcripts'}{$vname}{$tsi}{$dbname}++;
	}
      }
    }
  }
  store($ens_ids,$xref_file);
}


#this defines which external_db they match in Vega
my %vega_xref_names = (
 'shares_CDS_and_UTR_with_OTTT' => 'ENST_ident',
 'shares_CDS_with_OTTT'         => 'ENST_CDS',
 'OTTT'                         => 'ENST_ident',
 'OTTG'                         => 'ENSG',
);


#add xrefs to each E! object
foreach my $type (qw(genes transcripts)) {
  my $ids = $ens_ids->{$type};
  foreach my $v_id (keys %$ids) {
    my $adaptor = $type eq 'genes' ? $ga : $ta;
    my $object = $adaptor->fetch_by_stable_id($v_id);
    unless ($object) {
      $support->log_warning("Can't retrieve object $v_id from Vega\n");
      next;
    }
    $support->log_verbose("Studying object $v_id\n");
    my $c = {};
    while ( my ($e_id, $xrefs) =  each %{$ids->{$v_id}} ) {
    XREF:
      foreach my $dbtype (keys %$xrefs) {
        if ($c->{$e_id}{$dbtype}) {
          $support->log_warning("Multiple xrefs of dbtype $dbtype for $e_id and $v_id\n",1);
          next XREF;
        }
        my $vdb = $vega_xref_names{$dbtype};
        my $dbentry = Bio::EnsEMBL::DBEntry->new(
          -primary_id => $e_id,
          -display_id => $e_id,
          -version    => 1,
          -release    => 1,
          -dbname     => $vdb,
        );
        $type eq 'genes' ? $assigned_gxrefs{$vdb}->{$object->biotype}++ : $assigned_txrefs{$vdb}->{$object->biotype}++;
        $object->add_DBEntry($dbentry);
        if ($support->param('dry_run')) {
          $support->log_verbose("Would store $vdb xref $e_id for $v_id.\n", 1);
        }
        else {
          my $dbID = $ea->store($dbentry, $object->dbID, $type eq 'genes' ? 'gene' : 'transcript',1);
          if (! $dbID) {
            # apparently, this xref had been stored already, so get xref_id from db
            my $sql = qq(
               SELECT x.xref_id
                 FROM xref x, external_db ed
                WHERE x.external_db_id = ed.external_db_id
                  AND x.dbprimary_acc = '$e_id'
                  AND ed.db_name = '$vdb'
                         );
            ($dbID) = @{ $dbh->selectall_arrayref($sql) || [] };
            $support->log_warning("Reused $vdb xref $e_id for $v_id. Check why this should be\n");
          }
          if ($dbID) {
            $support->log_verbose("Stored $vdb xref $e_id for $v_id.\n", 1);
          }
        }
      }
    }
  }
}

#check which Vega genes / transcripts don't have xrefs
$support->log("Looking to see which genes / transcripts don't have e! xrefs\n\n");
my %ensembl_dbname = map {$_ => 1} %vega_xref_names;

my $chr_length = $support->get_chrlength($dba,$assembly,'',1);
my @chr_sorted = $support->sort_chromosomes($chr_length);
foreach my $chr (@chr_sorted) {
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n"); 
  my $slice = $sa->fetch_by_region('chromosome', $chr,undef,undef,undef,$assembly);
  unless (defined $slice) {
    $support->log_warning("No such chromosome '$chr'");
    next;
  }
  my ($genes) = $support->get_unique_genes($slice);
  foreach my $g (@$genes) {
    next unless $g->analysis->logic_name eq 'otter';
    next if $g->biotype =~ /TEC|artifact/;

    $support->log_verbose("Studying object ".$g->stable_id."\n",1);
    my $found = 0;
    foreach my $db_name (keys  %ensembl_dbname) {
      $found = 1 if @{$g->get_all_DBEntries($db_name)};
    }
    if (! $found) {
      $support->log("No E! xrefs found for gene ".$g->stable_id." (".$g->biotype.")\n",1);
    }
    foreach my $t (@{$g->get_all_Transcripts()}) {
      next if $t->biotype  =~ /TEC|artifact/;
      my $found = 0;
      foreach my $db_name (keys  %ensembl_dbname) {
        $found = 1 if @{$t->get_all_DBEntries($db_name)};
      }
      if (! $found) {
        $support->log("No E! xrefs found for transcript ".$t->stable_id." (".$t->biotype.")\n",2);
      }
    }
  }
}

$support->finish_log;

exit;
