#!/usr/local/bin/perl

=head1 NAME

fix_transcript_names.pl - update transcript names gene based names

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
in identical names for transcripts from the same gene then the transcripts are
numbered incrementaly after ordering from the longest coding to the shortest
non-coding. If any of these identical names are from transcripts that do not
overlap each other then a log is made and the ID dumped to file
(new_fragmented_gene_list.txt). These should be reported to Havana for double
checking they are not meant to be fragmented (see below). Using the verbose option
will also report where transcripts with identical names *do* overlap each other,
but this is probably unlikely to be very usefull.

The exceptions to this are genes that have a 'fragmented locus' gene_attrib
hidden_remark, or a '%fragmen%' transcript_attrib remark or hidden_remark
since these are truly fragmented. For these a human readable gene_attrib remark
is added and the transcript IDs are not updated. For genes that don't have such
a remark on the gene or a transcript, the stable_id is first compared against a
list of previously OKeyed genes - if any are seen then this is logged as they
really should have a remark (the stable ID is also saved in a file -
known_fragmented_gene_list.txt to facilitate this).

See vega_data_curation.txt for further details on using this script.

The -prune option restores the data to the stage before this script was first run.

The script can be used to change the root of transcript names either after the
addition of Zfin gene xrefs or after case mismatches in gene names have been fixed
- of course here the fix_duplicated names option should not be taken.

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
#genes that have been identified before but have no remark
my $k_flist_fh = $support->filehandle('>', $support->param('logpath').'/known_fragmented_gene_list.txt');
#new genes
my $n_flist_fh = $support->filehandle('>', $support->param('logpath').'/new_fragmented_gene_list.txt');

#get list of IDs that have previously been sent to annotators
my %seen_genes;
while (<DATA>) {
	next if /^\s+$/ or /#+/;
	my ($obj,$comment) = split /=/;
	$obj =~ s/^\s+|\s+$//g;
	$comment =~ s/^\s+|\s+$//g;
	$seen_genes{$obj} = $comment;
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

my ($c1,$c2,$c3,$c4) = (0,0,0,0);
foreach my $chr ($support->sort_chromosomes) {
	$support->log_stamped("Looping over chromosome $chr\n");
	my $slice = $sa->fetch_by_region('toplevel', $chr);
	foreach my $gene (@{$slice->get_all_Genes()}) {
		my $transnames;
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
				$support->log_warning("UNEXPECTED name for $ln transcript $tsi ($t_name), not updating.\n", 1);
			}
			else {
				$support->log("UNEXPECTED name for $ln transcript $tsi ($t_name), not updating.\n", 1);
			}	
		}
		if ( (grep { scalar(@{$transnames->{$_}}) > 1 } keys %{$transnames}) && $fix_names) {
			if (&update_names($gene)) {
				unless ( $seen_genes{$gsi} eq 'OK') {
					#decide what needs to be reported
					&check_names_and_overlap($transnames,$gene);
				}
			}
		}
	}
}
$support->log("Done updating $c1 xrefs and adding $c4 synonym transcript_attribs.\n");
$support->log("Patched names of $c3 transcripts from $c2 genes.\n");
$support->finish_log;

#check remarks - return 0 if 'fragmented' remarks are there.
#otherwise patch transcript names and return 1
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
	foreach my $type ('remark','hidden_remark') {
		$remarks{$type}->{'gene'} = [ map {$_->value} @{$gene->get_all_Attributes($type)} ];
		foreach my $trans (@{$ta->fetch_all_by_Gene($gene)}) {
			my $tsi = $trans->stable_id;
			push @{$remarks{$type}->{'transcripts'}}, map {$_->value} @{$trans->get_all_Attributes('remark')};
		}
	}

	#see if any of the remarks identify this gene as being known by Havana as being fragmented
	if ( (grep {$_ eq 'fragmented_locus'} @{$remarks{'hidden_remark'}->{'gene'}})
			 || (grep {$_ =~ /fragmen/} @{$remarks{'remark'}->{'transcripts'}})
				 || (grep {$_ =~ /fragmen/} @{$remarks{'hidden_remark'}->{'transcripts'}})
			 ) {
		if (grep { $_ eq $gene_remark} @{$remarks{'remark'}->{'gene'}}) {
			$support->log("Fragmented loci annotation remark for gene $gid already exists\n");
		}
		#add gene_attrib anyway
		else {
			if (! $support->param('dry_run') ) {
				$aa->store_on_Gene($gid,$attrib);
			}			
			$support->log("Added correctly formatted fragmented loci annotation remark for gene $gsi\n");
		}
		return 0;
	}
	#otherwise has it been reported before ? - log gsi since this should have a remark.
    #add gene_attrib anyway.
	elsif ($seen_genes{$gsi} eq 'fragmented') {
		$support->log_warning("PREVIOUS: Added correctly formatted fragmented loci annotation remark for gene $gsi (has previously been OKeyed by Havana as being fragmented but has no Annotation remark, please add one!)\n");
		print $k_flist_fh "$gsi\n";
		if (! $support->param('dry_run') ) {
			$aa->store_on_Gene($gid,$attrib);
		}
		return 0;
	}
	#otherwise patch transcript names
	else {
		$c2++;
		my @trans = $gene->get_all_Transcripts();
		#separate coding and non_coding transcripts
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
		$support->log("\nPatching names according to CDS and length:\n",1);
		foreach my $array_ref ($coding_trans,$noncoding_trans) {
			foreach my $trans ( sort { $b->length <=> $a->length } @$array_ref ) {
				my $tsi = $trans->stable_id;
				my $t_name = $trans->display_xref->display_id;
				$c++;
				my $ext = sprintf("%03d", $c);
				my $new_name = $g_name.'-'.$ext;
				$support->log(sprintf("%-20s%-3s%-20s", "$t_name ", "-->", "$new_name")."\n",1);
				if (! $support->param('dry_run')) {
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
	return 1;
}

sub check_names_and_overlap {
	my ($transcript_info,$gene) = @_;
	my $gsi = $gene->stable_id;
	my $g_name = $gene->get_all_Attributes('name')->[0]->value;
	foreach my $set (values %{$transcript_info} ) {
		next if (scalar @{$set} == 1);
		my $transcripts = [];
		my $all_t_names;

		#check for identical names
		my $duplicate = 0;
		foreach my $id1 (@{$set}) {
			my ($name1,$tsi1) = split /\|/, $id1;
			push @{$transcripts} , $ta->fetch_by_stable_id($tsi1);
			$all_t_names .= "$tsi1 ";
			foreach my $id2 (@{$set}) {
				my ($name2,$tsi2) = split /\|/, $id2;
				next if ($tsi1 eq $tsi2);
				$duplicate = 1 if ( $name1 eq $name2);
			}
		}
		if ($duplicate) {				
			$support->log_warning("IDENTICAL: Gene $gsi ($g_name) has transcripts with identical loutre names, please fix\n");
		}

		my $non_overlaps = $support->find_non_overlaps($transcripts);
		if (@{$non_overlaps}) {
			my $tsi_string = join ' ', @{$non_overlaps};
#			warn Dumper($non_overlaps);
#			exit;
	
			#log gsi (to be sent to Havana) if the transcripts don't overlap				
			$support->log_warning("NEW: Non-overlapping: $gsi ($g_name) has non-overlapping transcripts ($tsi_string) with duplicated names, and it has no \'Annotation_remark- fragmented_loci\' on the gene or \'\%fragmen\%\' remark on any transcripts. Neither has it been OKeyed by Havana before. Transcript names are being patched but this needs checking by Havana.\n");
			print $n_flist_fh "$gsi\n";
		}
		elsif ($support->param('verbose')) {
			$support->log_warning("NEW: Overlapping: $gsi ($g_name) has overlapping transcripts ($all_t_names) with duplicated names and it has no \'Annotation_remark- fragmented_loci\' on the gene or \'\%fragmen\%\' remark on any transcripts. Neither has it been OKeyed by Havana before. Transcript names are being patched but this could be checked by Havana if they were feeling keen.\n");
			print $n_flist_fh "$gsi\n";
		}
	}
}		


#details of genes with duplicated names that have already been reported to Havana
#OKeyed as either fragmented or OK
__DATA__


OTTMUSG00000005478 = fragmented
OTTMUSG00000001936 = fragmented
OTTMUSG00000017081 = fragmented
OTTMUSG00000011441 = fragmented
OTTMUSG00000013335 = fragmented
OTTMUSG00000011654 = fragmented
OTTMUSG00000001835 = fragmented
OTTMUSG00000012302 =
OTTMUSG00000013368 =
OTTMUSG00000015766 =
OTTMUSG00000016025 =
OTTMUSG00000001066 =
OTTMUSG00000016331 =
OTTMUSG00000006935 =
OTTMUSG00000007263 =
OTTMUSG00000000304 =
OTTMUSG00000009150 =
OTTMUSG00000008023 =
OTTMUSG00000017077 =
OTTMUSG00000003440 =
OTTMUSG00000016310 =
OTTMUSG00000026199 =
OTTMUSG00000028423 =
OTTMUSG00000007427 =
