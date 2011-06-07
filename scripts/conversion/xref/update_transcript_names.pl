#!/usr/bin/env perl

=head1 NAME

update_transcript_names.pl - update transcript names after changes to gene names

=head1 SYNOPSIS

fix_transcript_names.pl [options]

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
    --prune=0|1                         remove changes from previous runs of this script
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

=head1 DESCRIPTION

This script updates vega transcript xrefs after changes to gene names - these can
occur after patching of case differences or patching of mouse names after reference
to MGI records.

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

$| = 1;

my $support =  new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options('prune=s');
$support->allowed_params($support->get_common_params,'prune');

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $sa  = $dba->get_SliceAdaptor;
my $aa  = $dba->get_AttributeAdaptor;
my $dbh = $dba->dbc->db_handle;

# make a backup tables the first time the script is run
my @tables = qw(transcript xref object_xref);
my %tabs;
my $dbname = $support->param('dbname');
map { $_ =~ s/`//g; $_ =~ s/$dbname.//g; $tabs{$_} += 1; } $dbh->tables;
if (! exists ($tabs{'backup_utn_transcript'})) {
  foreach my $table (@tables) {
    my $t = 'backup_utn_'.$table;
    $support->log("Creating backup of $table\n\n");
    $dbh->do("CREATE table $t SELECT * FROM $table");
  }
}

if ($support->param('prune')
      && $support->user_proceed("\nDo you want to undo changes from previous runs of this script?")) {
  $support->log("Undoing changes from previous runs of this script...\n\n");
  foreach my $table (@tables) {
    my $t = 'backup_utn_'.$table;
    $dbh->do("DELETE from $table");
    $dbh->do("INSERT into $table SELECT * FROM $t");
  }
}

my ($c1,$c2) = (0,0);
foreach my $chr ($support->sort_chromosomes) {
  $support->log_stamped("\nLooping over chromosome $chr\n");
  my $chrom = $sa->fetch_by_region('toplevel', $chr);
 GENE:
  foreach my $gene (@{$chrom->get_all_Genes()}) {
    next unless ($gene->source =~ /havana|KO|WU/);
    my $gsi    = $gene->stable_id;
    my $g_name = $gene->display_xref->display_id;
    my $seen = 0;
  TRANS:
    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      my $tsi = $trans->stable_id;
      my $t_name = $trans->display_xref->display_id;
      my $orig_name = $t_name;
      unless ($t_name =~ /(\-\d{3})$/) {
	$support->log_warning("Gene $gsi ($g_name)- unexpected name for $tsi: $t_name. Skipping\n");
	next TRANS;
      }
      (my $version) = $t_name =~ /(\-\d{3})$/;
      $t_name =~ s/(\-\d{3})$//;
      if ($t_name eq $g_name) {
	next TRANS;
      }
      else {
	$c1++ unless $seen;
	$c2++;
	my $new_name = $g_name.$version;
	my $t_dbID = $trans->dbID;
	
	#store a transcript attrib for the old name as long as it's not just a case change
	unless (lc($orig_name) eq lc($new_name)) {
	  
	  $seen = 1;
	  my $attrib = [
	    Bio::EnsEMBL::Attribute->new(
	      -CODE => 'synonym',
	      -NAME => 'Synonym',
	      -DESCRIPTION => 'Synonymous names',
	      -VALUE => $orig_name,
	    )];
	  if (! $support->param('dry_run')) {
	    $aa->store_on_Transcript($t_dbID, $attrib);
	    $support->log_verbose("Stored synonym transcript_attrib for old name for transcript $tsi\n",2);
	  }
	}
	
	#update xref for new transcript name
	if (! $support->param('dry_run')) {
	  $dbh->do(qq(UPDATE xref x, external_db edb
                                   SET x.display_label = "$new_name"
                                 WHERE x.dbprimary_acc = "$tsi"
                                   AND x.external_db_id = edb.external_db_id
                                   AND edb.db_name = 'Vega_transcript'));
	}
	$support->log(sprintf("%-40s%-20s%-3s%-20s", "Gene $g_name ($gsi):", "$orig_name", "->", " $new_name")."\n", 1);
      }
    }
  }
}

$support->log("Done updating $c2 transcripts from $c1 genes.\n");
$support->finish_log;
