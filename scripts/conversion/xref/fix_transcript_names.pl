#!/usr/local/bin/perl

=head1 NAME

fix_transcript_names.pl - update transcript names with external names from genes

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

Specific options:

    --fix_xrefs, --fixxrefs=0|1         also fix xrefs

=head1 DESCRIPTION

This script updates vega transcript xrefs from the original clone-name
based transcript names to gene-name based ones.

If the option to fix duplicated names is chosen, then where the above results
in identical names for transcripts from the same gene then the transcripts are
numbered incrementaly after ordering from the longest coding to the shortest
non-coding.

The exceptions to this are genes that have a 'Annotation_remark - fragmented loci'
gene_attrib, or a '%fragmented%' transcript_attrib since these are truly fragmented.
For these a human readable gene_attrib remark is added and the transcript IDs are not
updated. For genes that don't have such a remark on the gene or a transcript, the stable_id
is first compared against a list of previously OKeyed genes -  if any are seen then
this is logged as they really should have a remark (the stable ID is also saved in a
file - known_fragmented_gene_list.txt to facilitate this). For genes that aren't in the
list then the transcript names are patched but these should also be reported back to
Havana for checking (again the stable IDS are dumped into a file (new_fragmented_gene_list.txt
to facilitate this).

The -prune option restores the data to the stage before this script was first run.

The script can be used to change the root of transcript names either after the addition of
Zfin gene xrefs or after case mismatches in gene names have been fixed - of course here the
fix_duplicated names option should not be taken.

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
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::Otter::GeneRemark;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

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
#genes that have been identified before but have no remark
my $k_flist_fh = $support->filehandle('>', $support->param('logpath').'/known_fragmented_gene_list.txt');
#new genes
my $n_flist_fh = $support->filehandle('>', $support->param('logpath').'/new_fragmented_gene_list.txt');

#get list of IDs that have previously been sent to annotators
my %seen_genes;
while (<DATA>) {
	next if /^\s+$/ or /#+/;
	$seen_genes{$_} = 1;
}

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $sa  = $dba->get_SliceAdaptor;
my $ga  = $dba->get_GeneAdaptor;
my $ta  = $dba->get_TranscriptAdaptor;
my $aa  = $dba->get_AttributeAdaptor;
my $dbh = $dba->dbc->db_handle;

# make a backup tables the first time the script is run
my @tables = qw(transcript xref transcript_attrib gene_attrib);
my %tabs;
map { $_ =~ s/`//g; $tabs{$_} += 1; } $dbh->tables;
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

my ($c1,$c2,$c3,$c4);
foreach my $chr ($support->sort_chromosomes) {
	$support->log_stamped("Looping over chromosome $chr\n");
	my $slice = $sa->fetch_by_region('toplevel', $chr);
	foreach my $gene (@{$slice->get_all_Genes()}) {
		my %transnames;
		my $g_name = $gene->display_xref->display_id;
		my $gsi    = $gene->stable_id;
		my $ln     = $gene->analysis->logic_name;
		$support->log("\n$g_name ($gsi)\n");
	TRANS: foreach my $trans (@{$gene->get_all_Transcripts()}) {
			my $t_name = $trans->display_xref->display_id;
			my $tsi    =  $trans->stable_id;
			my $t_dbID = $trans->dbID;
			if ($t_name =~ /(\-\d+)$/) {
				my $new_name = "$g_name$1";
				$transnames{$new_name}++;
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
						$c4++;
						$aa->store_on_Transcript($t_dbID, $attrib);
					}
					$support->log_verbose("Stored synonym transcript_attrib for old name for transcript $tsi\n",2);
				}

				#update xref for new transcript name
				if (! $support->param('dry_run')) {
					$c1++;
					$dbh->do(qq(
                        UPDATE  xref x, external_db ed
                        SET     x.display_label = "$new_name"
                        WHERE   dbprimary_acc = "$tsi"
                        AND     x.external_db_id = ed.external_db_id
                        AND     ed.db_name = "Vega_transcript"
                    ));
				}
				$support->log(sprintf("%-20s%-3s%-20s", "$t_name", "->", " $new_name")."\n", 1);
			}
			elsif ($ln eq 'otter') {
				$support->log_warning("Not updating transcript name for $ln transcript $tsi: unexpected transcript name ($t_name).\n", 1);
			}
			else {
				$support->log("Not updating transcript name for $ln transcript $tsi: unexpected transcript name ($t_name).\n", 1);
			}	
		}
		if ( (grep { $transnames{$_} > 1 } keys %transnames) && $fix_names) {
			&update_names($gene);
		}
	}
}
$support->log("Done updating $c1 xrefs and adding $c4 synonym transcript_attribs.\n");
$support->log("Patched names of $c3 transcripts from $c2 genes.\n");
$support->finish_log;


sub update_names {
	my ($gene) = @_;
	my $gsi    = $gene->stable_id;
	my $gid    = $gene->dbID;
	my $g_name = $gene->display_xref->display_id;
	my $gene_remark = 'This locus has been annotated as fragmented because either there is not enough evidence covering the whole locus to identify the exact exon structure of the transcript, or because the transcript spans a gap in  the assembly';
	my $attrib = [
		Bio::EnsEMBL::Attribute->new(
			-CODE => 'remark',
			-NAME => 'Remark',
			-DESCRIPTION => 'Annotation remark',
			-VALUE => $gene_remark,
		) ];
	#get gene and transcript remarks
	my %remarks;
	$remarks{'gene'} = [ map {$_->value} @{$gene->get_all_Attributes('remark')} ];
	foreach my $trans (@{$ta->fetch_all_by_Gene($gene)}) {
		my $tsi = $trans->stable_id;
		push @{$remarks{'transcripts'}}, map {$_->value} @{$trans->get_all_Attributes('remark')};
	}

	#see if any of the remarks identify this gene as being known by Havana as being fragmented
    #add gene_attrib anyway
	if ( (grep {$_ eq 'Annotation_remark- fragmented_loci'} @{$remarks{'gene'}})
			 || (grep {$_ =~ /fragmen/} @{$remarks{'transcripts'}}) ) {
		if (grep { $_ eq $gene_remark} @{$remarks{'gene'}}) {
			$support->log("Fragmented loci annotation remark for gene $gid already exists\n");
		}
		else {
			if (! $support->param('dry_run') ) {
				$aa->store_on_Gene($gid,$attrib);
			}			
			$support->log("Added correctly formatted fragmented loci annotation remark for gene $gsi\n");
			return;
		}
	}
	#otherwise has it been reported before ? - log ID gsi since this should have a remark (add gene_attrib anyway)
	elsif ($seen_genes{$gsi}) {
		$support->log_warning("Added correctly formatted fragmented loci annotation remark for gene $gsi (has previously been OKeyed by Havana as being fragmented but has no Annotation remark, please add one!)\n");
		print $k_flist_fh "$gsi\n";
		if (! $support->param('dry_run') ) {
			$aa->store_on_Gene($gid,$attrib);
		}
		return;
	}
	#otherwise patch transcript names and log gsi (to be sent to Havana)
	else {
		$c2++;
		$support->log_warning("$gsi ($g_name) has duplicated names and has no \'Annotation_remark- fragmented_loci\' on the gene or \'\%fragmen\%\' remark on any transcripts. Neither has it been OKeyed by Havana before. Transcript names are being patched but this ID should be reported to Havana for double checking\n");
		print $n_flist_fh "$gsi\n";
		my @trans = $gene->get_all_Transcripts();
		#seperate coding and non_coding transcripts
		my $coding_trans = [];
		my $noncoding_trans = [];
		foreach my $trans ( @{$gene->get_all_Transcripts()} ) {
			if ($trans->translate) {
				push @$coding_trans, $trans;
			}
			else {
				push @$noncoding_trans, $trans;
			}
		}
		my $c = 0;
		#sort transcripts coding > non-coding, then on length
		foreach my $array_ref ($coding_trans,$noncoding_trans) {
			foreach my $trans ( sort { $b->length <=> $a->length } @$array_ref ) {
				my $tsi = $trans->stable_id;
				my $t_name = $trans->display_xref->display_id;
				$c++;
				my $ext = sprintf("%03d", $c);
				my $new_name = $g_name.'-'.$ext;
				$support->log(sprintf("%-20s%-3s%-20s", "$t_name ", "-->", "$new_name")."\n");
				unless ($support->param('dry_run')) {
					# update transcript name
					if ($dbh->do(qq(UPDATE  xref x, external_db edb
                                SET     x.display_label  = "$new_name"
                                WHERE   x.external_db_id = edb.external_db_id
                                AND     x.dbprimary_acc  = "$tsi"
                                AND     edb.db_name      = "Vega_transcript")) ) {
						$c3++;
					}
				}
			}
		}		
	}			
}	

#add details of genes with duplicated names that have already been reported to Havana...
__DATA__

OTTMUSG00000005478
OTTMUSG00000001936
OTTMUSG00000003440
OTTMUSG00000017081
OTTMUSG00000016310
OTTMUSG00000011441
OTTMUSG00000012302
OTTMUSG00000013368
OTTMUSG00000013335
OTTMUSG00000015766
OTTMUSG00000016025
OTTMUSG00000001066
OTTMUSG00000016331
OTTMUSG00000006935
OTTMUSG00000011654
OTTMUSG00000001835
OTTMUSG00000007263
OTTMUSG00000000304
OTTMUSG00000009150
OTTMUSG00000008023
OTTMUSG00000017077
