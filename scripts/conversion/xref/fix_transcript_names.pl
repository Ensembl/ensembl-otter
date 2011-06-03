#!/usr/bin/env perl

=head1 NAME

fix_transcript_names.pl - update transcript names to gene based one

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

This script updates vega transcript xrefs from the original clone-name
based transcript names to gene-name based ones.

If the option to fix duplicated names is chosen, then where the above results
in identical names for transcripts from the same gene, then the transcripts are
numbered incrementaly after ordering from the longest coding to the shortest
non-coding. If any of these identical names are from transcripts that have not
been seen before then the ID is dumped to file (new_fragmented_gene_list.txt).
These should be reported to Havana for double
checking they are not meant to be fragmented (see below). Using the verbose option
will also report on non-havana loci.

See vega_data_curation.txt for further details on using this script and getting usefull
reports from the log file

The -prune option restores the data to the stage before this script was first run.

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
  unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::VegaCuration::Transcript;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::VegaCuration::Transcript($SERVERROOT);

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

#set filehandle for logging of gene IDs
#new genes
my $n_flist_fh = $support->filehandle('>', $support->param('logpath').'/new_fragmented_gene_list.txt');

#get list of IDs that have previously been sent to annotators
my $seen_genes = $support->get_havana_fragmented_loci_comments;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $sa  = $dba->get_SliceAdaptor;
my $aa  = $dba->get_AttributeAdaptor;
my $dbh = $dba->dbc->db_handle;

# make a backup tables the first time the script is run
my $dbname = $support->param('dbname');
my @tables = qw(transcript xref transcript_attrib gene_attrib);
my %tabs;
map { $_ =~ s/`//g; $_ =~ s/$dbname.//g; $tabs{$_} += 1; } $dbh->tables;
if (! exists ($tabs{'backup_ftn_transcript'})) {
  foreach my $table (@tables) {
    my $t = 'backup_ftn_'.$table;
    $support->log("Creating backup of $table\n\n");
    $dbh->do("CREATE table $t SELECT * FROM $table");
  }
}

#are duplicate transcript names going to be fixed later on ?
my $fix_names = 0;
if ($support->user_proceed("\nDo you want to check and fix duplicated transcript names?") ) {
  $fix_names = 1;
}

if ($support->param('prune')
      && $support->user_proceed("\nDo you want to undo changes from previous runs of this script?")) {
  $support->log("Undoing changes from previous runs of this script...\n\n");
  foreach my $table (@tables) {
    my $t = 'backup_ftn_'.$table;
    $dbh->do("DELETE from $table");
    $dbh->do("INSERT into $table SELECT * FROM $t");
  }
}

my ($c1,$c2,$c3) = (0,0,0);
foreach my $chr ($support->sort_chromosomes) {
  $support->log_stamped("\n\nLooping over chromosome $chr\n");
  my $chrom = $sa->fetch_by_region('toplevel', $chr);
 GENE:
  foreach my $gene (@{$chrom->get_all_Genes()}) {
    
    my $gsi    = $gene->stable_id;
    my $transnames;
    my %seen_names;
    my %transcripts;
    my $g_name = $gene->display_xref->display_id;
    my $source = $gene->source;

    $support->log("\n$g_name ($gsi)\n");

    #check for identical names in loutre
    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      my $t_name = $trans->get_all_Attributes('name')->[0]->value;
 #     $t_name = $trans->display_xref->display_id;
      #remove unexpected extensions but report them for fixing (should be caught now)
      my $base_name = $t_name;
      if ( ($base_name =~ s/-\d{1,2}$//)
	     || ($base_name =~ s/__\d{1,2}$//)
	       || ($base_name =~ s/__\d{1,2}$//)
		 || ($base_name =~ s/_\d$//)
	           || ($base_name =~ s/\.\d+$//)) {
	unless ( ($support->param('dbname') =~ /rerio/) && ($chr eq 'AB')) {
	  $support->log_warning("UNEXPECTED transcript name $t_name\n");
	}
      }
			
      #warn duplicated names (should all be caught by the QC now)
      if (exists $seen_names{$base_name}) {
        $support->log_warning("IDENTICAL: $source gene $gsi ($g_name) has transcripts with identical base loutre names ($base_name), please fix\n");
      }

      else {
	$seen_names{$base_name}++;
	$transcripts{$t_name} = [$trans,$base_name];
      }
    }
		
    #patch names
  TRANS:
    foreach my $t_name (keys %transcripts) {
      my $trans = $transcripts{$t_name}->[0];
      my $base_name = $transcripts{$t_name}->[1];
      my $tsi    =  $trans->stable_id;
      my $t_dbID = $trans->dbID;		
      if ( ($t_name =~ /([\-\.]\d{3})$/) || ($t_name =~ /(\-\d{3})[_-]\d{1}$/) ) { #hack to patch dodgy names that haven't been fixed (esp Danio)
	my $new_name = "$g_name$1";
	push @{$transnames->{$new_name}}, "$t_name|$tsi";
	next if ($new_name eq $t_name);
	
	#store a transcript attrib for the old name as long as it's not just a case change
	my $attrib = [
	  Bio::EnsEMBL::Attribute->new(
	    -CODE => 'synonym',
	    -NAME => 'Synonym',
	    -DESCRIPTION => 'Synonymous names',
	    -VALUE => $t_name,
	  )];
	unless (lc($t_name) eq lc($new_name)) {
	  if (! $support->param('dry_run')) {
	    $aa->store_on_Transcript($t_dbID, $attrib);
	  }
	  $support->log_verbose("Stored synonym for old name ($t_name) for transcript $tsi\n",2);
	}
	$c1++;
	
	#update xref for new transcript name
	if (! $support->param('dry_run')) {
	  $dbh->do(qq(
                        UPDATE  xref x, external_db ed
                        SET     x.display_label = "$new_name"
                        WHERE   dbprimary_acc = "$tsi"
                        AND     x.external_db_id = ed.external_db_id
                        AND     ed.db_name = "Vega_transcript"
                    ));
	}
	$support->log(sprintf("%-20s%-3s%-20s", "$t_name", "--->", " $new_name")."\n", 1);
      }

      #log unexpected names (ie don't have -001 etc after removing Leo's extension
      else {
	$support->log_warning("Can't patch transcript $t_name ($tsi) because name is wrong\n");
      }
    }

    #if there are duplicated names in Vega then patch, add proper remark if they are fragmented
    if ( (grep { scalar(@{$transnames->{$_}}) > 1 } keys %{$transnames}) && $fix_names) {
      my $patched;
      ($patched,$c2,$c2) = $support->check_remarks_and_update_names($gene,$c2,$c3);
      if ($patched) {
	unless ( $seen_genes->{$gsi} eq 'OK') {
	  #distinguish between overlaping and non-overlapping genes for reporting
	  $support->check_names_and_overlap($transnames,$gene,$n_flist_fh);
	}
      }
    }
  }
}
$support->log("Done updating xrefs for $c1 transcripts\n");
$support->log("Identified $c3 transcripts from $c2 genes as updatable.\n");
$support->finish_log;
