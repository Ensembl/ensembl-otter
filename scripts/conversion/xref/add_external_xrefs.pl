#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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

add_external_xrefs.pl - adds xrefs to external databases from various types
of input files

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

    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gene_stable_id, --gsi=LIST|FILE   only process LIST gene_stable_ids
                                        (or read list from FILE)
    --xrefformat=FORMAT                 input file format FORMAT
                                        (hugo|tcag|imgt|refseq)
    --hgncfile=FILE                     read Hugo input from FILE
    --mgivega=FILE                      read MGI<->Vega ID links from FILE
    --mgi=FILE                          read MGI data from FILE
    --tcagfile=FILE                     read TCAG input from FILE
    --imgt_hlafile=FILE                 read IMGT_HLA input from FILE
    --rgdfile=FILE                      read RGT input from file
    --refseqfile=FILE                   read Refseq input from FILE
    --mismatch                          correct case mismatches in the db
                                          overrides dry-run, doesn't add xrefs
    --onlydb=NAME,NAME                  only add DBs NAME, NAME (HGNC ONLY!)
    --prune                             reset to the state before running this
                                        script (i.e. after running
                                        add_vega_xrefs.pl)
    --verbose                           dump data structure from parsing of input file

    --namefixesfile=FILENAME            also write namefixes to given file
    --nolocal                           fail if remote retrieval fails

=head1 DESCRIPTION

This script parses input files from various sources - HGNC, MGI, TCAG (human chr 7 annotation),
IMGT (human major histocompatibility complex nomenclature), and an Ensembl
database - and adds xrefs to the databases covered by the respective input source. If
appropriate the display names of genes are set accordingly. Data structures for the input files
are stored to disc (so are only parsed once)

It's worthwhile running the script first with -dry_run and -mismatch options to fix any
case errors in the Vega gene_names. Then run it normally to add xrefs. Note that if any
gene_names are found to have case errors then the transcript names must also be updated
using patch_transcript_names.pl.

IMGT_HLA is used to add xrefs for HLA genes on human haplotypes.
IMGT_GDB is used to add xrefs for IG genes

For mouse, mgi xrefformat adds links both to MGI and to external databases.

For rat, rgd adds links to MGI, Uniprot, RefSeq, PubMed and EntrezGene

Currently, these input formats are supported:

    hgnc        => http://www.genenames.org/cgi-bin/hgnc_downloads.cgi
                   - use the URL shown in the parse_hgnc method below, or just let lwp do it for you
    mgi         => mgifile = ftp://ftp.informatics.jax.org/pub/reports/MRK_List2.rpt (all current MGI symbols)
                   mgifile_uni_ref = ftp://ftp.informatics.jax.org/pub/reports/MRK_Sequence.rpt [links between marker symbols and TrEMBL / RefSeq])
                   mgifile_entrez = ftp://ftp.informatics.jax.org/pub/reports/MGI_Gene_Model_Coord.rpt [links between marker symbols and Entrezgene])
                   - use these URLs for manual download or just let LWP do it
    rgd         => ftp://ftp.rgd.mcw.edu/pub/data_release/GENES_RAT.txt (lwp does it for you)
    imgt_hla    => by email Steven Marsh <marsh@ebi.ac.uk>
    imgt_gdb    => use vega database


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
use LWP::UserAgent;

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
  'xrefformat=s',
  'hgncfile=s',
  'mgifile=s',
  'mgifile_uni_ref=s',
  'mgifile_entrez=s',
  'rgdfile=s',
  'imgt_hlafile=s',
  'namefixesfile=s',
  'rgdfile=s',
  'onlydb=s',
  'mismatch',
  'prune',
  'nolocal',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
  'xrefformat',
  'hgncfile',
  'mgifile',
  'mgifile_uni_ref',
  'mgifile_entrez',
  'rgdfile',
  'imgt_hlafile',
  'namefixesfile',
  'rgdfile',
  'onlydb',
  'mismatch',
  'prune',
  'nolocal',
);

$support->check_required_params('xrefformat');	

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

if($support->param('namefixesfile')) {  
  open(NAMEFIX,">",$support->param('namefixesfile')) or die "Cannot create ".$support->param('namefixesfile')."\n";
}

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa  = $dba->get_SliceAdaptor();
my $ga  = $dba->get_GeneAdaptor();
my $ea  = $dba->get_DBEntryAdaptor();

# statement handle for display_xref_id update
my $sth_display_xref = $dba->dbc->prepare("UPDATE gene SET display_xref_id=? WHERE gene_id=?");

# statement handles for fixing case errors
my $sth_case = $dba->dbc->prepare("UPDATE xref set display_label = ? WHERE display_label = ?");

# delete external xrefs if --prune option is used; removes only those added using this source (hgnc, imgt etc)
if ($support->param('prune') and $support->user_proceed('Would you really like to delete xrefs from previous runs of this script that have used these options?')) {
  my %refs_to_delete = (
    imgt_hla => qq(= 'IMGT_HLA'),
    imgt_gdb => qq(= 'IMGT/GENE_DB'),
  );

  # xrefs
  my $num = 0;
  $support->log("Deleting  external xrefs...\n");
  my $cond = $refs_to_delete{$support->param('xrefformat')}
    || qq(not in ('Vega_gene','Vega_transcript','Vega_translation','Interpro','CCDS','Havana_gene','ENSG','ENST','ENST_CDS','ENST_ident','IMGT_HLA','IMGT/GENE_DB','GO','Quick_Go','Quick_Go_Evidence'));
	
  $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name $cond));
  $support->log("Done deleting $num entries.\n",1);

  # object_xrefs
  $num = 0;
  $support->log("Deleting orphan object_xrefs...\n");
  $num = $dba->dbc->do(qq(
           DELETE ox
           FROM object_xref ox
           LEFT JOIN xref x ON ox.xref_id = x.xref_id
           WHERE x.xref_id IS NULL
        ));
  $support->log("Done deleting $num entries.\n",1);

  # external_synonyms
  $num = 0;
  $support->log("Deleting orphan external_synonyms...\n");
  $num = $dba->dbc->do(qq(
           DELETE es
           FROM external_synonym es
           LEFT JOIN xref x ON es.xref_id = x.xref_id
           WHERE x.xref_id IS NULL
        ));
  $support->log("Done deleting $num entries.\n",1);

  #reset display xrefs to gene stable ID unless we're using one of the specific formats
  unless ($refs_to_delete{$support->param('xrefformat')}) {
    $support->log("Resetting gene.display_xref_id...\n");
    $num = $dba->dbc->do(qq(
           UPDATE gene g, xref x
           SET g.display_xref_id = x.xref_id
           WHERE g.stable_id = x.dbprimary_acc
        ));
    $support->log("Done resetting $num display_xrefs.\n");
  }
}

my %gene_stable_ids = map { $_, 1 }  $support->param('gene_stable_id');
my $chr_length = $support->get_chrlength($dba,'','',1);
my @chr_sorted = $support->sort_chromosomes($chr_length);

no strict 'refs';
my $parsed_xrefs = {};
my $lcmap = {};	
my $format = ($support->param('xrefformat'));
my $xref_file    = $SERVERROOT.'/'.$support->param('dbname')."-$format-parsed_records.file";
my $lc_xref_file = $SERVERROOT.'/'.$support->param('dbname')."-$format-lc-parsed_records.file";

# read input files... either retrieve from disc
if (-e $xref_file) {
  if ($support->user_proceed("Read xref records from a previously saved files - $xref_file ?\n")) {
    $parsed_xrefs = retrieve($xref_file);
    $lcmap = retrieve($lc_xref_file);
  }
  #or parse..
  else {
    $support->log_stamped("Reading xref input files...\n");
    my $parser = "parse_$format";
    &$parser($parsed_xrefs, $lcmap);
    $support->log_stamped("Finished parsing xrefs, storing to file...\n");
    store($parsed_xrefs,$xref_file);
    store($lcmap,$lc_xref_file);
  }
}
		
#or parse..
else {
  $support->log_stamped("Reading xref input files...\n");
  my $parser = "parse_$format";
  &$parser($parsed_xrefs, $lcmap);
  $support->log_stamped("Finished parsing xrefs, storing to file...\n");
  store($parsed_xrefs,$xref_file);
  store($lcmap,$lc_xref_file);
}

if ( $support->param('verbose') ) {
  $support->log("Parsed xrefs are ".Dumper($parsed_xrefs)."\n");
  $support->log("Parsed lc xrefs are ".Dumper($lcmap)."\n");
}

use strict 'refs';
$support->log_stamped("Done.\n\n");

if ($support->param('xrefformat') eq 'imgt_hla') {
  foreach my $gsi (keys %{$parsed_xrefs}) {
    unless (my $gene  = $ga->fetch_by_stable_id($gsi) ) {
      $support->log_warning("Cannot retrieve $gsi from Vega database\n");
    }
  }
}

# define xrefs that can be set, what type each xref is, and whether to set as display_xref or not
my %extdb_def = (
  HGNC                     => ['KNOWNXREF', 1],
  EntrezGene               => ['KNOWNXREF', 0],
  MGI                      => ['KNOWNXREF', 1],
  RGD                      => ['KNOWNXREF', 1],
  RefSeq_dna               => ['KNOWN'    , 0],
  RefSeq_dna_predicted     => ['PRED'     , 0],
  RefSeq_peptide           => ['KNOWN'    , 0],
  RefSeq_peptide_predicted => ['PRED'     , 0],
  RefSeq_rna               => ['KNOWN'    , 0],
  RefSeq_rna_predicted     => ['PRED'     , 0],
  RefSeq_genomic           => ['KNOWN'    , 0],
  MIM_GENE                 => ['KNOWNXREF', 0],
  PUBMED                   => ['KNOWN'    , 0],
  TCAG                     => ['KNOWN'    , 0],
  IMGT_HLA                 => ['KNOWN'    , 0],
  'IMGT/GENE_DB'           => ['KNOWN'    , 0],
  'Uniprot/SWISSPROT'      => ['KNOWN'    , 0],
);

# loop over chromosomes
$support->log("Looping over chromosomes: @chr_sorted\n\n");
my $seen_xrefs;
my (%overall_stats,%overall_xrefs);

foreach my $chr (@chr_sorted) {

  ####
  #if you're working on ensembl-vega then switch these next two lines around, otherwise you
  #won't get haplotypes and patch genes
  ####
#  my $slice = $sa->fetch_by_region('chromosome', $chr,undef,undef,undef,'GRCh37');
  my $slice = $sa->fetch_by_region('chromosome', $chr);

  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n");

  # fetch genes from db
  my $genes;
  if ($slice) {
    $support->log("Fetching genes...\n",1);
    ($genes) = $support->get_unique_genes($slice);
  }
  else {
    $support->log_warning("Can't get a slice for $chr\n",1);
    next;
  }
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n",1);

  # loop over genes
  my %stats = map { $_ => 0 } keys %extdb_def;
  my %xrefs_assigned = (
    'assigned'             => 0,
    'no display xref'      => 0,
    'wrong case'           => 0,
    'nomatch - clone name' => 0,
    'nomatch'              => 0,
  );
  my $gnum = 0;
 GENE:
  foreach my $gene (@$genes) {
    my $gsi = $gene->stable_id;
    my $gid = $gene->dbID;
    my $gene_name;

    # filter to user-specified gene_stable_ids
    if (scalar(keys(%gene_stable_ids))){
      next GENE unless $gene_stable_ids{$gsi};
    }
		
    # catch missing display_xrefs here (shouldn't be any)
    my $disp_xref = $gene->display_xref;
    if ($disp_xref) {
      $gene_name = $disp_xref->display_id;
    } else {
      $support->log_warning("No display_xref found for gene $gid ($gsi). Have you run add_vega_xrefs.pl ? Skipping.\n");
      $xrefs_assigned{'no display xref'}++;
      next GENE;
    }

    $support->log("Studying gene $gene_name ($gsi)...\n");
    $gnum++;

    my ($real_name,$prefix);	
    # strip prefixes off the name if the gene has one (ie is external)
    unless ( ($prefix,$real_name) = $gene_name  =~ /(.*?):(.*)/) {
      $real_name = $gene_name;
    }	

    #look for case mismatches if that's what's wanted - will do both internal and external genes
    if ($support->param('mismatch')) {
      if (! $parsed_xrefs->{$real_name} ) {
	my $lc_name = lc($real_name);
	if (my $n = $lcmap->{$lc_name}->[0]) {
	  my $new_name =  $prefix ? $prefix.':'.$n : $n;
	  $support->log_warning("Gene $gsi has a name of $gene_name but should be $new_name\n",1);
    if($support->param('namefixesfile')) {
      print NAMEFIX "Gene $gsi has a name of $gene_name but should be $new_name\n";
    }
	  if (! $support->param('dry_run')) {
	    #update gene_name and display_xref
	    $support->log("Fixing case mismatch $gene_name to $new_name...\n", 1);
	    $sth_case->execute($new_name, $gene_name);
	    $xrefs_assigned{'wrong case'}++;
	  }
	}
      }
    }
    else {
      #get all names to search on
      my @gene_names;
      push @gene_names, $real_name;

      #use previously set MarkerSymbol xrefs as searchable names
      if ( $support->param('xrefformat') eq 'mgi') {
	foreach my $xref (@{$gene->get_all_DBEntries}) {
	  if ($xref->dbname eq 'MarkerSymbol') {
	    my $mgi_name = $xref->display_id;
	    unless (grep {$_ eq $mgi_name} @gene_names) {
	      push @gene_names, $xref->display_id;
	    }
	  }
	}
      }

      #look only for stable_ids for certain types of record
      if ($support->param('xrefformat') =~ /imgt|mgivega/) {
	@gene_names = ( $gsi );
      }

      #get a list of names of databases for existing xrefs on this gene
      my %existing_dbnames;
      foreach my $xref (@{$gene->get_all_DBEntries}){
	my $dbname = $xref->dbname;
	$existing_dbnames{$dbname} = 1;
      }
      my $xref_found = 0;
    NAME:
      foreach my $name (@gene_names) {
	next if $xref_found;
	
	my $update_xref = 1;
	my $display_filter;
		
	$support->log("Searching for name $name...\n",1);
	if (my $links = $parsed_xrefs->{$name}) {

	  $support->log("Match found for $name.\n",1);

          my $synonyms = $links->{'Synonyms'} || [];

	DB: foreach my $db (keys %{$links}) {
            next DB if $db eq 'Synonyms';

            #only go further with this external_db if we've allowed it in the hash above.
            next DB unless $extdb_def{$db};

	    $support->log_verbose("Assessing link to $db\n",2);

	    #sanity check - don't go any further if this gene already has an xref for this source
	    if ($existing_dbnames{$db}) {
	      $support->log("$db xref previously set for gene $gene_name ($gsi), not storing a new one.\n", 1);
	      next DB;
	    }
	    $stats{$db}++;
			
	    foreach my $concat_xid ( @{$links->{$db}} ) {
	      my $dbentry;

	      #catch empty xrefs
	      if (!$concat_xid || $concat_xid =~ /^\|\|$/) {
		$support->log_verbose("No details found for database $db\n",3);
		next DB;
	      }

	      my ($xid,$pid) = split /\|\|/, $concat_xid;

	      unless ($xid && $pid) {
		$support->log_warning("Parsed file not in the correct format, please check\n");
		next DB;
	      }

	      #use an existing xref if there is one...
	      my ($existing_xref,$dbID);
	      $existing_xref = $ea->fetch_by_db_accession($db,$pid);

	      if ($existing_xref && $existing_xref->display_id eq $xid) {
                #add synonyms if there are any
                if ($extdb_def{$db}->[1] && @$synonyms ) {
                  foreach my $syn (@$synonyms) {
                    $support->log_verbose("Adding synonym $syn for $db xref $xid\n",3);
                    $existing_xref->add_synonym($syn);
                  }
                }
		my $old_dbID = $existing_xref->dbID;
		$support->log_verbose("Using previous $db xref ($old_dbID) for gene $gene_name ($gsi).\n", 3);
		$gene->add_DBEntry($existing_xref);
		if (! $support->param('dry_run')) {
		  $dbID = $ea->store($existing_xref, $gid, 'gene');
		}
	      }

	      #... or else create a new one
	      else {
		$support->log_verbose("Creating new $db xref for gene $gene_name ($gsi).\n", 3);
		$dbentry = Bio::EnsEMBL::DBEntry->new(
		  -primary_id => $pid,
		  -display_id => $xid,
		  -version    => 1,
		  -dbname     => $db,
		);
                #add synonyms if there are any
                if ($extdb_def{$db}->[1] && @$synonyms ) {
                  foreach my $syn (@$synonyms) {
                    $support->log_verbose("Adding synonym $syn for $db xref $xid\n",3);
                    $dbentry->add_synonym($syn);
                  }
                }
		$dbentry->status($extdb_def{$db}->[0]); ##is this necc?
		$gene->add_DBEntry($dbentry);
		if (! $support->param('dry_run')) {
		  $dbID = $ea->store($dbentry, $gid, 'gene', 1);
		}
	      }
	      #was the store succesfull ?
	      if ($dbID) {
		$support->log("Stored $db xref (display_id = $xid, pid = $pid) for gene $gene_name ($gsi)\n", 2);
	      }
	      elsif (! $support->param('dry_run')) {
		$support->log_warning("Failed to store $db xref for gene $gene_name ($gsi)\n");
	      }

	      #do we want to update the display_xref ?
	      if ($extdb_def{$db}->[1]) {
		
		#if there's no prefix it's easy -  use the xref just created
		if (! $prefix) {
                  $support->log_verbose("Updating display_xref for gene $gene_name, using $gid\n",2);
		  if (! $support->param('dry_run')) {
		    $sth_display_xref->execute($dbID,$gid);
		    $support->log("UPDATED display xref (pid = $dbID) for $gene_name ($gsi).\n",2);	
		  }
		}
				
		#if there is a prefix then we need another xref
		else {
                  my $info_text = ($prefix eq 'KO') ? 'vega_source_prefix_ko' : 'vega_source_prefix';
                  $support->log_verbose("Creating new display_xref for gene $gene_name\n",2);
		  my $new_dbentry = Bio::EnsEMBL::DBEntry->new(
		    -primary_id => $pid,
		    -display_id => $gene_name,
		    -version    => 1,
		    -dbname     => $db,
		    -info_text  => $info_text,
		  );
		  if (! $support->param('dry_run')) {
		    my $new_dbID = $ea->store($new_dbentry, $gid, 'gene', 1);
		    $sth_display_xref->execute($new_dbID,$gid);	
		    $support->log("UPDATED display xref (pid = $new_dbID) for gene $gene_name ($gsi) using prefixed name\n",3);	
		  }
		}
	      }
	    }
	  }												
	}
	else {
	  $support->log("No match found for $name.\n",1);
	  if ($gene_name =~ /^\w+\.\d+$/ || $gene_name =~ /^\w+\-\w+\.\d+$/) {
	    # probably a clone-based genename - ok
	    $support->log("...but has clonename based name.\n", 2);
	    $xrefs_assigned{'nomatch -clone name'}++;
	    next GENE;
	  }
	  else {
	    # other genes without a match
	    $xrefs_assigned{'nomatch'}++;
	    next GENE;
	  }
	}
      }
    }
  }
    
  # log stats
  $support->log("\nProcessed $gnum genes (of ".scalar @$genes." on this chromosome).\n");
  $support->log("OK:\n");
  foreach my $extdb (sort keys %stats) {
    $support->log("$extdb $stats{$extdb}.\n", 1);
  }
  $support->log("Genes with possible case mismatch: $xrefs_assigned{'wrong case'}.\n", 1);
  $support->log("Genes with apparently clonename based names: $xrefs_assigned{'nomatch -clone name'}.\n", 1);
  $support->log("Other genes without match: $xrefs_assigned{nomatch}.\n", 1);
  $support->log_stamped("Done with chromosome $chr.\n\n");
  
  $overall_stats{$chr}    = \%stats;
  $overall_xrefs{$chr} = \%xrefs_assigned;
}

#create a summary of stats
my (%report_s,%report_w);
foreach my $chr_name (keys %overall_stats) {
  foreach my $extdb (sort keys %{$overall_stats{$chr_name}}) {
    $report_s{$extdb} += $overall_stats{$chr_name}->{$extdb};
  }
}
$support->log("\nSummary of xrefs assigned
-------------------------\n\n");
foreach my $extdb (keys %report_s) {
  $support->log("$extdb provides $report_s{$extdb} xrefs\n",1);
}

#create a summary of warnings
foreach my $chr_name (keys %overall_xrefs) {
  foreach my $cat (sort keys %{$overall_xrefs{$chr_name}}) {
    $report_w{$cat} += $overall_xrefs{$chr_name}->{$cat};
  }
}

$support->log("\nSummary of errors
-------------------------\n\n");	
foreach my $cat (keys %report_w) {
  $support->log("$cat - $report_w{$cat}\n",1);
}

if($support->param('namefixesfile')) {
  close NAMEFIX;
}

# finish log
$support->finish_log;


=head2 parse_ensdb

  Arg[1]      : Hashref $xrefs - keys: gene names, values: hashref (extDB => extID)
  Example     : &parse_ensdb($ens_xrefs);
                foreach my $gene (keys %$ens_xrefs) {
                    foreach my $extdb (keys %{ $ens_xrefs->{$gene} }) {
                        print "DB $extdb, extID ".$ens_xrefs->{$gene}->{$extdb}."\n";
                    }
                }
  Description : Parses stable IDs xrefs from an E! core database where the display_xref is unique
  Return type : none
  Exceptions  : thrown if database can't be read
  Caller      : Not called anywhere at all now, just kep in in case we ever need it!

=cut

sub parse_ensdb {
  my ($xrefs) = @_;
  $dba = $support->get_database('ensembl', 'ensembl');
  my $sa = $dba->get_SliceAdaptor();
  my $e_dbname = $support->param('ensembldbname');
  $support->log_stamped("Retrieving xrefs from $e_dbname...\n", 1);
  
  #get xrefs from Ensembl db where the display xref matches is a hgnc one
  my ($e_xrefs,$seen_names);
  foreach my $chr ( @{$sa->fetch_all('chromosome')} ) {
    my $chr_name = $chr->seq_region_name;
    $support->log("Looking at chromosome $chr_name\n",1);
    
    foreach my $gene ( @{$chr->get_all_Genes} ) {
      next unless (my $disp_xref = $gene->display_xref);
      next unless ($disp_xref->dbname =~ /HGNC/);
      my $stable_id = $gene->stable_id;
      my $gene_name = $disp_xref->display_id;
      #only use HGNC names that are unique to e! genes
      $seen_names->{$gene_name}++;
      if ( $seen_names->{$gene_name} > 1 ) {
	$support->log_verbose("DUPLICATE: Ensembl gene $gene_name not unique, deleting stable id $stable_id\n",2);
	delete($e_xrefs->{$gene_name}{'stable_id'});
      }
      else {
	$support->log_verbose("Storing Ensembl stable_id $stable_id\n",2);
	$e_xrefs->{$gene_name}{'stable_id'} = $stable_id;
      }
    }
  }

  #add these to the hgnc xrefs
  foreach my $name (keys %{$e_xrefs}) {
    if ( exists($xrefs->{$name}) ) {
      my $stable_id = $e_xrefs->{$name}{'stable_id'};
      push @{$xrefs->{$name}->{'Ens_Hs_gene'}}, $stable_id.'||'.$stable_id;
    }
  }
}

=head2 parse_hgnc

  Arg[1]      : Hashref $xrefs - keys: gene names, values: hashref (extDB =>
                extID)
  Arg[2]      : Hashref $lcmap - keys: lowercase gene names, values: list of
                gene names (with case preserved)
  Example     : &parse_hgnc($xrefs, $lcmap);
                foreach my $gene (keys %$xrefs) {
                    foreach my $extdb (keys %{ $xrefs->{$gene} }) {
                        print "DB $extdb, extID ".$xrefs->{$gene}->{$extdb}."\n";
                    }
                }
  Description : Downloads from HGNC, or parses a data file manually downloaded from HGNC
                [HGNC record has supplied IDs for Omim, curated IDs for RefSeq and Pubmed
  Return type : none
  Exceptions  : thrown if input file can't be read
  Caller      : internal

=cut

sub parse_hgnc {
  my ($xrefs, $lcmap) = @_;
  $support->log_stamped("HGNC...\n", 1);

 my $url = "http://www.genenames.org/cgi-bin/hgnc_downloads?col=gd_hgnc_id&col=gd_app_sym&col=gd_status&col=gd_aliases&col=gd_pub_eg_id&col=gd_pubmed_ids&col=gd_pub_refseq_ids&col=md_mim_id&col=md_prot_id&status=Approved&status_opt=2&where=&order_by=gd_hgnc_id&format=text&limit=&hgnc_dbtag=on&submit=submit";


  #try and download direct
  my $ua = LWP::UserAgent->new;
  $ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');
  my $resp = $ua->get($url);
  my $page = $resp->content;
  if ($page) {
    $support->log("File downloaded from HGNC\n",1);
  }
  else {
    if($support->param('nolocal')) {
      $support->log_error("Couldn't retrieve file and --nolocal given");
    }
    # read input file from HGNC
    $support->log("Unable to download from HGNC, trying to read from disc: ".$support->param('hgncfile')."\n",1);
    open (NOM, '<', $support->param('hgncfile')) or $support->throw(
      "Couldn't open ".$support->param('hgncfile')." for reading: $!\n");
    $page = do { local $/; <NOM> };
  }
  my @recs = split "\n", $page;

  #define which columns to parse out of the record
  #key = column title, value = external_db.name (apart from status which is used to check symbol has not been withdrawn)
  my %wanted_columns = (
    'HGNC ID'         => 'HGNC_PID',
    'Approved Symbol' => 'HGNC',
    'Status'          => 'Status',
    'Synonyms'        => 'Synonyms',
    'Pubmed IDs'      => 'PUBMED',
    'Entrez Gene ID'  => 'EntrezGene',
    'OMIM ID'         => 'MIM_GENE',
    'RefSeq IDs'      => 'RefSeq',
  );

  #define relationships between RefSeq accession number and database (this is not in the download file)
  my %refseq_dbs = (
    NM => 'RefSeq_dna',
    XM => 'RefSeq_dna_predicted',
    NP => 'RefSeq_peptide',
    XP => 'RefSeq_peptide_predicted',
    NR => 'RefSeq_rna',
    XR => 'RefSeq_rna_predicted',
    NG => 'RefSeq_genomic',
    NT => 'RefSeq_genomic',
  );

  # read header (containing external db names) and check all wanted columns are there
  my ($status_column,%fieldnames);
  my $line = $recs[0];
  chomp $line;
  my @columns =  split /\t/, $line;
  foreach my $wanted (keys %wanted_columns) {
    my $found = 0;
    foreach my $i (0..$#columns) {
      if($columns[$i] =~ /$wanted/) {
        $fieldnames{$i} = $wanted_columns{$wanted};
        $status_column = $i if $wanted eq 'Status';
        $found = 1;
        last;
      }
    }
    unless($found) {
      $support->log_error("Can't find $wanted column in HGNC record: $line\n");
    }
  }

  my %stats = (
    total      => 0,
    withdrawn  => 0,
  );

  # prime with prefixes we don't care about
  my %report_once = ( YP => 1, NC => 1 );
  #parse records, storing only data in those columns defined above
  #also ignore 'withdrawn' symbols
 REC:
  foreach my $l (@recs) {
    $stats{'total'}++;
    chomp $l;
    my @fields = split /\t/, $l, -1;
    my %accessions;
    my $gene_name;

    #check that the symbol is not withdrawn
    if ($fields[$status_column] =~ /withdrawn/) {
      $support->log_verbose("You have a withdrawn symbol in the download. Ignoring it but no need to download these\n");
      $stats{'withdrawn'}++;
      next REC;
    }

    foreach my $i (keys %fieldnames) {
      my $type = $fieldnames{$i};
      next if $type eq 'Status';
      if ($type eq 'HGNC') {
	$gene_name = $fields[$i];
      }
      if ($fields[$i]) {
	$accessions{$type} = $fields[$i];
      }
    }

    #set records for each gene
    foreach my $db (keys %accessions) {
      next if ($db eq 'HGNC_PID');
      next if($support->param('onlydb')
        and not grep { $_ eq $db } split(/,/,$support->param('onlydb')));

      #set record where display name and pid are different
      if ($db eq 'HGNC') {
	$xrefs->{$gene_name}->{$db}[0] = $gene_name .'||'. $accessions{'HGNC_PID'};
      }
      elsif ($db eq 'EntrezGene') {
	$xrefs->{$gene_name}->{$db}[0] = $gene_name .'||'. $accessions{$db};
      }

      #set RefSeq records to the correct type of molecule
      elsif ($db =~ 'RefSeq') {
	foreach my $record (split ',', $accessions{$db}) {
          $record =~ s/^\s+|\s+$//g; #whitespace
          if (my ($prefix) = $record =~ /^([A-Z]{2})_/) {
            if (my $type = $refseq_dbs{$prefix}) {
              push @{$xrefs->{$gene_name}->{$type}}, $record .'||'. $record;
            }
            elsif (! $report_once{$prefix}) {
              $report_once{$prefix}++;
              $support->log_warning("RefSeq prefix $prefix not recognised\n");
            }
          }
	}
      }

      #set PUBMED records where you can have more than one per record
      elsif ($db eq 'PUBMED') {
	foreach my $record (split ',', $accessions{$db}) {
	  $record =~ s/^\s+//;
	  $record =~ s/\s+$//;
	  push @{$xrefs->{$gene_name}->{$db}}, $record.'||'.$record;
	}
      }

      #get synonyms
      elsif ($db eq 'Synonyms') {
	foreach my $record (split ',', $accessions{$db}) {
	  $record =~ s/^\s+//;
	  $record =~ s/\s+$//;
	  push @{$xrefs->{$gene_name}->{$db}}, $record;
	}
      }
      #get rest of xrefs where the pid is the same as the name
      else {
	push @{$xrefs->{$gene_name}->{$db}}, $accessions{$db}.'||'. $accessions{$db};
      }
    }

    #store lowercase name for matching
    push @{ $lcmap->{lc($gene_name)} }, $gene_name;
  }

  close(NOM);

  $support->log_stamped("Done processing ".$stats{'total'}." records:\n", 1);
  $support->log("$stats{'withdrawn'} gene names withdrawn\n", 1);
}


=head2 parse_rgd

  Arg[1]      : Hashref $xrefs - keys: gene names, values: hashref (extDB =>
                extID)
  Arg[2]      : Hashref $lcmap - keys: lowercase gene names, values: list of
                gene names (with case preserved)
  Example     : &parse_rgd($xrefs, $lcmap);
                foreach my $gene (keys %$xrefs) {
                    foreach my $extdb (keys %{ $xrefs->{$gene} }) {
                        print "DB $extdb, extID ".$xrefs->{$gene}->{$extdb}."\n";
                    }
                }
  Description : Downloads and parses a file from RGD, or parses a file previously downloaded
  Return type : none
  Exceptions  : thrown if input file can't be read
  Caller      : internal

=cut

sub parse_rgd {
  my ($xrefs, $lcmap) = @_;
  $support->log_stamped("RGD...\n", 1);

  my $url = "ftp://ftp.rgd.mcw.edu/pub/data_release/GENES_RAT.txt";

  #try and download direct
  my $ua = LWP::UserAgent->new;
  $ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');
  my $resp = $ua->get($url);
  my $page = $resp->content;
  if ($page) {
    $support->log("File downloaded from RGD\n",1);
  }
  else {
    if($support->param('nolocal')) {
      $support->log_error("Couldn't retrieve file and --nolocal given");
    }
    # read input file
    $support->log("Unable to download from RGD, trying to read from disc: ".$support->param('rgdfile')."\n",1);
    open (NOM, '<', $support->param('rgdfile')) or $support->throw(
      "Couldn't open ".$support->param('rgdfile')." for reading: $!\n");
    $page = do { local $/; <NOM> };
  }
  my @recs = split "\n", $page;

  #define which columns to parse out of the record
  #key = column title, value = external_db.name (apart from status which is used to check symbol has not been withdrawn)
  my %wanted_columns = (
    'GENE_RGD_ID'           => 'RGD_PID',
    'SYMBOL'                => 'RGD',
    'CURATED_REF_PUBMED_ID' => 'PUBMED',
    'ENTREZ_GENE'           => 'EntrezGene',
    'UNIPROT_ID'            => 'Uniprot/SWISSPROT',
    'GENBANK_NUCLEOTIDE'    => 'RefSeq_dna',
    'GENBANK_PROTEIN'       => 'RefSeq_peptide',
  );

  #define relationships between RefSeq accession number and database (this is not in the download file)
  my %refseq_dbs = (
    NM => 'RefSeq_dna',
    XM => 'RefSeq_dna_predicted',
    NP => 'RefSeq_peptide',
    XP => 'RefSeq_peptide_predicted',
    NR => 'RefSeq_rna',
    XR => 'RefSeq_rna_predicted',
    NG => 'RefSeq_genomic',
    NT => 'RefSeq_genomic',
  );

  # prime with prefixes we don't care about
  my %report_once = ( YP => 1, NC => 1, NW => 1, AP => 1 );

  my %stats = (
    total      => 0,
  );

  # read header (containing external db names) and check all wanted columns are there
  my %fieldnames;
  while( my $line = shift @recs) {
    next if $line =~ /^#/;
    chomp $line;
    my @columns =  split /\t/, $line;
    foreach my $wanted (keys %wanted_columns) {
      unless (grep { /$wanted/ } @columns ) {
        $support->log_error("Can't find $wanted column in HGNC record: $line\n");
      }
    }

    #make a note of positions of wanted fields
    for (my $i=0; $i < scalar(@columns); $i++) {
      my $column_label =  $columns[$i];
      next if (! $wanted_columns{$column_label});
      $fieldnames{$i} = $wanted_columns{$column_label};
    }
    last;
  }

  #parse records, storing only data in those columns defined above
 REC:
  foreach my $l (@recs) {
    $stats{'total'}++;
    chomp $l;
    my @fields = split /\t/, $l, -1;
    my %accessions;
    my $gene_name;

    foreach my $i (keys %fieldnames) {
      my $type = $fieldnames{$i};
      if ($type eq 'RGD') {
	$gene_name = $fields[$i];
      }
      if ($fields[$i]) {
	$accessions{$type} = $fields[$i];
      }
    }

    #set records for each gene
    foreach my $db (keys %accessions) {
      next if ($db eq 'RGD_PID');
      #set record where display name and pid are different
      if ($db eq 'RGD') {
	$xrefs->{$gene_name}->{$db}[0] = $gene_name .'||'. $accessions{'RGD_PID'};
      }
      elsif ($db eq 'EntrezGene') {
	$xrefs->{$gene_name}->{$db}[0] = $gene_name .'||'. $accessions{$db};
      }
      #set RefSeq records to the correct type of molecule
      elsif ($db =~ /RefSeq/) {
        my @records = split ';',$accessions{$db};
        foreach my $rec (@records) {
          if (my ($prefix) = $rec =~ /^([A-Z]{2})_/) {
            if (my $type = $refseq_dbs{$prefix}) {
              push @{$xrefs->{$gene_name}->{$type}}, $rec .'||'. $rec;
            }
            elsif (! $report_once{$prefix}) {
              $report_once{$prefix}++;
              $support->log_warning("RefSeq prefix $prefix not recognised\n");
            }
          }
	}
      }

      #set PUBMED / Uniprot records where you can have more than one per record
      elsif ($db =~ /PUBMED|Uniprot/) {
	foreach my $record (split ';', $accessions{$db}) {
	  $record =~ s/^\s+//;
	  $record =~ s/\s+$//;
	  push @{$xrefs->{$gene_name}->{$db}}, $record.'||'.$record;
	}
      }

      #get rest of xrefs where the pid is the same as the name
      else {
	push @{$xrefs->{$gene_name}->{$db}}, $accessions{$db}.'||'. $accessions{$db};
      }
    }

    #store lowercase name for matching
    push @{ $lcmap->{lc($gene_name)} }, $gene_name;
  }

  close(NOM);

  $support->log_stamped("Done processing ".$stats{'total'}." records:\n", 1);
}


=head2 parse_mgivega

  Arg[1]      : Hashref $xrefs - keys: gene names, values: hashref (extDB =>
                extID) 
  Arg[2]      : Hashref $lcmap - keys: lowercase gene names, values: list of
                gene names (with case preserved)
  Example     : &parse_mgi($xrefs, $lcmap);
  Description : Parses a specific rtf file from MGI. Used to add links between
                MarkerSymbol and Vega genes
  Return type : none
  Exceptions  : thrown if input file can't be read
  Caller      : internal
  Status      : Deprecated (used to be used to assocaiate OTT and MGI but
                this is now done by anacode)

=cut

sub parse_mgivega {
  my ($xrefs) = @_;
  $support->log_stamped("MGI...\n", 1);
  
  # read input file
  my $mgivegafile = $support->param('mgivegafile');
  open(MGIV, "< $mgivegafile")
    or $support->throw("Couldn't open $mgivegafile for reading: $!\n");
  
  #parse input file
  while (<MGIV>) {
    chomp;
    my @fields = split /\t/;
    my $pid = $fields[0];
    my $markersymbol = $fields[1];
    my $desc = $fields[2];
    my $vegaID = $fields[5];
    if ( exists($xrefs->{$vegaID}) ) {
      $support->log_warning("$vegaID found more than once in MGI file. Symbol\n");
    }
    push @{$xrefs->{$vegaID}{'MarkerSymbol'}}, $markersymbol . '||' . $pid;
  }
}

=head2 parse_mgi

  Arg[1]      : Hashref $xrefs - keys: gene names, values: hashref (extDB =>
                extID) 
  Arg[2]      : Hashref $lcmap - keys: lowercase gene names, values: list of
                gene names (with case preserved)
  Example     : &parse_mgi($xrefs, $lcmap);
  Description : Parses a specific rtf file from MGI. Used to add MarkerSymbol, Swissprot
                RefSeq and EntrezGene xrefs to Vega genes
  Return type : none
  Exceptions  : thrown if input file can't be read
  Caller      : internal

=cut

sub parse_mgi {
  my ($xrefs, $lcmap) = @_; 

  #define which columns to parse out of the record. Note this does parse Uniprot although we don't add this to the genes
  #(we use ad_ebi_xrefs.pl to add it to the transcripts)
  my $wanted_columns = {
    'mgifile' => {
      'MGI Accession ID'        => 'MGI_PID',
      'Marker Symbol'           => 'MGI',
    },
    'mgifile_entrez' => {
      '1. MGI accession id'     => 'MGI_PID',
      '3. marker symbol'        => 'MGI',
      '6. Entrez gene id'       => 'EntrezGene',
    },
    'mgifile_uni_ref' => {
      'MGI Marker Accession ID' => 'MGI_PID',
      'Marker Symbol'           => 'MGI',
      'RefSeq transcript IDs'   => 'RefSeq_dna',
      'RefSeq protein IDs'      => 'RefSeq_peptide',
      'TrEMBL IDs'               => 'TrEMBL',
    },
  };

  my %file_urls = (
    mgifile => "ftp://ftp.informatics.jax.org/pub/reports/MRK_List2.rpt",
    mgifile_entrez => "ftp://ftp.informatics.jax.org/pub/reports/MGI_Gene_Model_Coord.rpt",
    mgifile_uni_ref => "ftp://ftp.informatics.jax.org/pub/reports/MRK_Sequence.rpt",
  );

  foreach my $file (sort keys %$wanted_columns) {

    # read input file
    $support->log_stamped("$file...\n", 1);
  
    #try and download direct
    my $ua = LWP::UserAgent->new;
    $ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');
    my $url = $file_urls{$file};
    my $resp = $ua->get($url);
    my $page = $resp->content;
    if ($page) {
      $support->log("$url downloaded from MGI\n",1);
    } else {
      if($support->param('nolocal')) {
        $support->log_error("Couldn't retrieve file and --nolocal given");
      }
      my $mgifile = $support->param($file);
      open(MGI, "< $mgifile")
        or $support->throw("Couldn't open $mgifile for reading: $!\n");
      my $page = do { local $/; <MGI> };
      close MGI;
    }
    my @recs = split "\n", $page;

    # read header containing column titles and check all wanted columns are there
    my $line = shift @recs;
    chomp $line;
    my @columns =  split /\t/, $line;

    foreach my $wanted (keys %{$wanted_columns->{$file}}) {
      unless (grep { $_ eq $wanted} @columns ) {
        $support->log_error("Can't find $wanted column in MGI record\n");
      }
    }

    #make a note of positions of wanted fields
    my %fieldnames;
    for (my $i=0; $i < scalar(@columns); $i++) {
      my $column_label = $columns[$i];
      next if (! $wanted_columns->{$file}{$column_label});
      $fieldnames{$i} = $wanted_columns->{$file}{$column_label};
    }

    #parse input file
  REC:
    foreach my $l (@recs) {
      chomp $l;
      my @fields = split /\t/, $l, -1;
      my %accessions;
      my $marker_symbol;

      foreach my $i (keys %fieldnames) {
        my $type = $fieldnames{$i};
        if ($type eq 'MGI') {
          $marker_symbol = $fields[$i];
        }
        if ($fields[$i]) {
          $accessions{$type} = $fields[$i];
        }
      }

      foreach my $db (keys %accessions) {
        if ($db eq 'MGI') {
          $xrefs->{$marker_symbol}{$db} = [ $marker_symbol .'||'. $accessions{'MGI_PID'} ] unless $xrefs->{$marker_symbol}{$db};
        }
        elsif ( $db =~ /RefSeq/) {
          foreach my $acc (split (/\|/, $accessions{$db})) {
            $db = 'RefSeq_peptide_predicted' if ($acc =~ /^XP_/);
            push @{$xrefs->{$marker_symbol}{$db}}, $acc .'||'. $acc ;
            $db = 'RefSeq_peptide';
          }
        }
        elsif ( $db ne 'MGI_PID') {
          foreach my $acc (split (/\|/, $accessions{$db})) {
            push @{$xrefs->{$marker_symbol}{$db}}, $acc .'||'. $acc ;
          }
        }
      }
      push @{ $lcmap->{lc($marker_symbol)} }, $marker_symbol unless $lcmap->{lc($marker_symbol)};
    }
  }
}


=head2 parse_tcag

=cut

sub parse_tcag {
  my ($xrefs, $lcmap) = @_;
  $support->log_stamped("TCAG...\n", 1);
  
  # read input file
  my $tcagfile = $support->param('tcagfile');
  my $fh_expr;
  if($tcagfile =~ /\.gz$/) {
    $fh_expr = "gzip -d -c $tcagfile |";
  } else {
    $fh_expr = "< $tcagfile";
  }
  open(TCAG, $fh_expr)
    or $support->throw("Couldn't open $tcagfile for reading: $!\n");
	
  #parse input file
  while (<TCAG>) {
    my @fields = split /\t/;
    next unless  $fields[8] =~ /Gene_ID/;
    my @details = split /;/, $fields[8];
    my ($symbol) = $details[0] =~ /"(.+)"/;
    next if ($symbol =~ /transcript_variant/);
    my ($id)     = $details[2] =~ /"(.+)"/;
    
    #for debugging
    unless ($symbol && $id) {
      print "record with no symbol = $_\n";
      foreach my $f (@fields) {
	print " field = $f\n";
      }
      foreach my $d (@details) {
	print "  det = $d\n";
      }
    }
    
    push @{$xrefs->{$symbol}->{'TCAG'}} , $id.'||'.$id;
    push @{ $lcmap->{lc($symbol)} }, $symbol;
  }
}

=head2 parse_imgt_hla

=cut

sub parse_imgt_hla {
  my ($xrefs, $lcmap) = @_;
  $support->log_stamped("IMGT_HLA...\n", 1);
  # read input file from IMGT
  open (IMGT, '<', $support->param('imgt_hlafile')) or $support->throw(
    "Couldn't open ".$support->param('imgt_hlafile')." for reading: $!\n");
  # read header
  my $line = <IMGT>;
  my @fieldnames = split /\t/, $line;
  while (<IMGT>) {
    chomp;
    s/ //g;
    my @fields = split /\t/, $_;
    my $xid  = $fields[1];
    my $gsi = $fields[0];
    my $pid = $xid;
    $pid =~ s/\*/_/; 
    push @{$xrefs->{$gsi}->{'IMGT_HLA'}} , $xid.'||'.$pid;
  }
}

=head2 parse_imgt_gdb

=cut

sub parse_imgt_gdb {
  my ($xrefs, $lcmap) = @_;
  $support->log_stamped("IMGT_GDB...\n", 1);
  my $sql = qq(SELECT g.stable_id, x.display_label
                 FROM gene g, xref x
                WHERE g.display_xref_id = x.xref_id
                  AND g.source = 'havana'
                  AND g.biotype in ('IG_gene','IG_pseudogene','TR_gene','TR_pseudogene'));
  my $sth = $dba->dbc->prepare($sql);
  $sth->execute;
  while ( my ($gsi, $id) = $sth->fetchrow_array) {		
    push @{$xrefs->{$gsi}->{'IMGT/GENE_DB'}} , $id.'||'.$id;
  }
}
