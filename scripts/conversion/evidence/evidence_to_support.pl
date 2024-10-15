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

evidence_to_support.pl - script to add supporting evidence to a Vega database

=head1 SYNOPSIS

evidence_to_support.pl [options]

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
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gene_stable_id, --gsi=LIST|FILE   only process LIST gene_stable_ids
                                        (or read list from FILE)
    --check_evidence_table              examine links between evidence and align_feature tables
                                        (for data curation)

=head1 DESCRIPTION

This script adds the supporting evidence for Vega. It does so by comparing
accessions between annotated evidence and similarity features from the protein
and dna align feature tables. If a match is found, it is added to the supporting_feature
and transcript_supporting_feature tables.

Pseudocode:

    foreach gene
        get all similarity features, store in datastructure
        foreach transcript
            get all annotated evidence
            foreach evidence
                foreach similarity feature
                    accession matches?
                        foreach exon
                            similarity feature overlaps exon?
                                store supporting evidence

There are occasions where no match for annotated evidence can be found.
Possible reasons for this are: spelling mistake by annotator; feature not found
by protein pipeline run (e.g. removed from external database, renamed); small
features found by Dotter and not by Blixem. The genes and transcripts without any
evidence are reported by source (GC, havana etc), as are the evidence table entries
that do not link to the align_feature tables (if check_evidence_table option is explicitly
set to 1, this check is disabled by default). Log output when checking evidence is long,
even more so when it is verbose (for example reports stable IDs of all external genes
without evidence and all evidence table entries that don't match to align_feature tables)

- genes without any evidence at all:
   $ grep 'No supporting feature' evidence_to_support.log

- transcripts with no evidence:
   $ grep 'No evidence for' evidence_to_support.log

- evidence table entries not matched in align_feature tables:
   $ grep 'accessions match' evidence_to_support.log

There is no prune option - changes can be easily undone by deleting entries from
transcript_supporting_feature and supporting_feature


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
  unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/sanger-plugins/vega/modules");
  unshift(@INC, "$SERVERROOT/ensembl-variation/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
### PARALLEL # $support ###

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'chromosomes|chr=s@',
  'gene_stable_id|gsi=s@',
  'check_evidence_table=s',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'gene_stable_id',
  'check_evidence_table',
  'prune',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->list_or_file('gene_stable_id');

#do not check evidence table by default
$support->param('check_evidence_table',0) unless defined($support->param('check_evidence_table'));

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors (caching features on one slice only)
my $dba = $support->get_database('loutre');
my $sa = $dba->get_SliceAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $aa = $dba->get_AnalysisAdaptor();

if ($support->param('prune') and $support->user_proceed('Would you really like to delete all supporting features ?')) {
  my $num = $dba->dbc->do(qq(DELETE FROM supporting_feature));
  $support->log("Deleted $num supporting_features");
  $num = $dba->dbc->do(qq(DELETE FROM transcript_supporting_feature));
  $support->log("Deleted $num transcript_supporting_features");
}

# statement handles for storing supporting evidence
my $sth = $dba->dbc->prepare(qq(
    INSERT INTO supporting_feature
        (exon_id, feature_id, feature_type)
    VALUES(?, ?, ?)
));
my $sth1 = $dba->dbc->prepare(qq(
    INSERT INTO transcript_supporting_feature
        (transcript_id, feature_id, feature_type)
    VALUES(?, ?, ?)
));

my @gene_stable_ids = $support->param('gene_stable_id');
my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;

#get chromosomes
my $chr_length = $support->get_chrlength($dba,'','chromosome',1); #will retrieve non-reference slices

my %analysis = map { $_->logic_name => $_ } @{ $aa->fetch_all };
my %ftype = (
  'Bio::EnsEMBL::DnaDnaAlignFeature' => 'dna_align_feature',
  'Bio::EnsEMBL::DnaPepAlignFeature' => 'protein_align_feature',
);

#set up data structures to store details of which evidence table entries are in the align_feature tables
#my %evidence_stats = map {$_ => 0 } qw(evidence_with_match evidence_without_match evidence_without_covered_match);
my $all_alignments = {};
my $all_evidence = {};

my $stats;
my %transcripts_without_support;
my %genes_without_support;
my %transcripts_without_evidence;
my %genes_without_evidence;

### PRE # # $stats %transcripts_without_support %genes_without_support %transcripts_without_evidence %genes_without_evidence $all_alignments $all_evidence ###

# loop over chromosomes
my @chr_sorted = $support->sort_chromosomes($chr_length);
$support->log("Looping over chromosomes: @chr_sorted\n\n");

### RUN # @chr_sorted ###

foreach my $chr (@chr_sorted) {
  my %chr_stats;
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");

  # fetch genes from db
  $support->log("Fetching genes...\n");
  my $slice = $sa->fetch_by_region('toplevel', $chr);
  my $genes = $slice->get_all_Genes;
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");

  # loop over genes
  foreach my $gene (@$genes) {
    my $gsi = $gene->stable_id;
    my $gid = $gene->dbID;

    #use original loutre name attributes since likely to be reporting back to Havana
    my $gene_name = $gene->get_all_Attributes('name')->[0]->value;
#    my $gene_name = $gene->display_xref->display_id;

    my $source = $gene->source;

    #skip KO genes since they shouldn't have supporting evidence
    next if ($gene->analysis->logic_name =~ /eucomm|komp/);

    # filter to user-specified gene_stable_ids
    if (scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }

    # adjust gene's slice to cover gene +/- 1000 bp
    my $gene_slice = $sa->fetch_by_region('toplevel', $chr, $gene->start - 1000, $gene->end + 1000);
    $gene = $gene->transfer($gene_slice);
    unless ($gene) {
      $support->log_warning("Gene $gene_name ($gid, $gsi) doesn't transfer to padded gene_slice.\n");
      next;
    }

    $stats->{$source}{'genes'}++;
    $chr_stats{'genes'}++;
    my %se_hash = ();
    my %tse_hash = ();
    my $gene_has_support = 0;
    my $gene_has_evidence = 0;
    $support->log_verbose("Gene $gene_name ($gid, $gsi) on slice ".$gene->slice->name."...\n");

    # fetch similarity features from db and store required information in
    # lightweight datastructure (name => [ start, end, dbID, type ])
    $support->log_verbose("Fetching similarity features...\n",1);
    my $similarity = $gene_slice->get_all_SimilarityFeatures;
    my $sf = {};
    foreach my $f (@$similarity) {
      (my $hitname = $f->hseqname) =~ s/\.[0-9]*$//;
      push @{ $sf->{$hitname} },
	[ $f->start, $f->end, $f->dbID, $ftype{ref($f)} ];
    }
    $support->log_verbose("Done fetching ".(scalar @$similarity)." features\n", 1);

    # loop over transcripts
    my ($e_match,$t_match) = 0,0;
    foreach my $trans (@{ $gene->get_all_Transcripts }) {
      my $transcript_has_support = 0;
      my $transcript_has_evidence = 0;
      $stats->{$source}{'transcripts'}++;
      $chr_stats{'transcripts'}++;
      my $tsid = $trans->stable_id;
      $support->log_verbose("Transcript $tsid...\n", 1);

      # loop over evidence added by annotators for this transcript
      my @evidence = @{$trans->evidence_list};
      my @exons = @{ $trans->get_all_Exons };
      $stats->{$source}{'exons'} += scalar(@exons);
      $chr_stats{'exons'} += scalar(@exons);
      foreach my $evi (@evidence) {
	$transcript_has_evidence = 1;
	$gene_has_evidence = 1;
	my $acc = $evi->name;
	$acc =~ s/.*://;
	my $acc_ver = $acc;
	$acc =~ s/\.[0-9]*$//;
	my $acc_type = $evi->type;
	$all_evidence->{$source}{$acc_type}{"$acc: $tsid:$acc_ver"}++;
	my $ana = $analysis{$evi->type . "_evidence"};
	$support->log_verbose("Evidence $acc...\n", 2);
	# loop over similarity features on the slice, compare name with
	# evidence
	my $hit_match = 0;
	foreach my $hitname (keys %$sf) {
	  if ($hitname eq $acc) {
	    foreach my $hit (@{ $sf->{$hitname} }) {
	      # store transcript supporting evidence
	      if ($trans->end >= $hit->[0] && $trans->start <= $hit->[1]) {
		# store unique evidence identifier in hash
		$tse_hash{$trans->dbID.":".$hit->[2].":".$hit->[3]} = 1;
		$hit_match = 1;
		$t_match = 1;
		$gene_has_support++;
		$transcript_has_support++;
	      }

	      # loop over exons and look for overlapping similarity features
	      foreach my $exon (@exons) {
		if ($exon->end >= $hit->[0] && $exon->start <= $hit->[1]) {
		  $support->log_verbose("Matches similarity feature with dbID ".$hit->[2].".\n", 3);
                  # store unique evidence identifier in hash
		  $se_hash{$exon->dbID.":".$hit->[2].":".$hit->[3]} = 1;
		  $e_match = 1;
		}
	      }
	    }
	  }
	}
	if (!$hit_match) {
	  $support->log_verbose("No matching similarity feature found for $acc.\n", 3);
	}
      }

      #sanity check
      if ($e_match && !$t_match) {
	$support->log_warning("I don't understand how we can have supporting_features but no transcript_supporting_features for $tsid\n");
      }

      my $id = $trans->stable_id." on gene $gsi (chr $chr)";
      unless ($transcript_has_support) {
	$stats->{$source}{'transcripts_without_support'}++;
	push @{$transcripts_without_support{$source}}, $id;
      }
      unless ($transcript_has_evidence) {
	$stats->{$source}{'transcripts_without_evidence'}++;
	push @{$transcripts_without_evidence{$source}}, $id;
      }
    }

    my $id = "$gsi (chr $chr)";
    unless ($gene_has_support) {
      $stats->{$source}{'genes_without_support'}++;
      push @{$genes_without_support{$source}}, $id;
    }
    unless ($gene_has_evidence) {
      $stats->{$source}{'genes_without_evidence'}++;
      push @{$genes_without_evidence{$source}}, $id;
    }
    $support->log_verbose("Found $gene_has_support matches (".
			    scalar(keys %se_hash)." unique).\n", 1);

    # store supporting evidence in db
    if (! $support->param('dry_run')) {
      foreach my $tse (keys %tse_hash) {
	eval {
	  $sth1->execute(split(":", $tse));
	};
	$support->log_warning("$gsi: $@\n", 1) if ($@);
      }
    }

    if ($gene_has_support and ! $support->param('dry_run')) {
      $support->log_verbose("Storing supporting evidence... ". $support->date_and_mem."\n", 1);
      foreach my $se (keys %se_hash) {
	eval {
	  $sth->execute(split(":", $se));
	};
	if ($@) {
	  $support->log_warning("$gsi: $@\n", 1);
	}
      }
      $support->log_verbose("Done storing evidence. ". $support->date_and_mem."\n", 1);
    }
  }
  $support->log("\nProcessed $chr_stats{genes} genes (of ".scalar @$genes." on chromosome $chr), $chr_stats{transcripts} transcripts, $chr_stats{exons} exons.\n");
  $support->log("Done with chromosome $chr. ".$support->date_and_mem."\n\n");
}

### POST ###

#summarise genes missing support / evidence
foreach my $source (keys %{$stats}) {

  #only show Havana missing evidence unless we really want to!
  next if ( ($source ne 'havana') && (! $support->param('verbose')) );

  #summarise genes with no supporting_features and evidence
  if (my $g_no_support = $stats->{$source}{'genes_without_support'}) {
    $support->log("\nLooking at $source genes for missing supporting_features:\n");
    my $tot_genes  = $stats->{$source}{'genes'};
    my $perc_genes = $g_no_support / $tot_genes * 100;
    $support->log("$source: No supporting_features for any transcripts on $g_no_support out of $tot_genes ($perc_genes %) genes.\n", 1);
    $support->log_verbose("Genes without supporting_features:\n", 1);
    foreach my $g (@{$genes_without_support{$source}}) {
      #does this one have any evidence at all ?
      my $extra = (grep {$g eq $_} @{$genes_without_evidence{$source}} ) ? ' (no evidence at all)' : '';
      $support->log_verbose("$g$extra\n", 2);
    }
  }
  #summarise transcripts with no supporting_features and evidence
  if (my $t_no_support = $stats->{$source}{'transcripts_without_support'}) {
    my $tot_transcripts = $stats->{$source}{'transcripts'};
    my $perc_transcripts = $t_no_support / $tot_transcripts * 100;
    $support->log("$source: No supporting_features for $t_no_support out of $tot_transcripts ($perc_transcripts) transcripts.\n", 1);
    $support->log_verbose("Transcripts without supporting features:\n", 1);
    foreach my $t (@{$transcripts_without_support{$source}}) {
      #does this one have any evidence at all ?
      my $extra = (grep {$t eq $_ } @{$transcripts_without_evidence{$source}}) ? ' (no evidence at all)' : '';
      $support->log_verbose("$t$extra\n", 2);
    }
  }
}

if ($support->param('check_evidence_table')) {
  $support->log("\n\nExamining links between evidence table and align_feature tables\n");
  foreach my $t ('dna_align_feature','protein_align_feature') {
    $support->log_stamped("Retrieving features from $t\n",1);
    my $sth = $dba->dbc->prepare(qq(Select hit_name from $t));
    $sth->execute;
    while (my ($name) = $sth->fetchrow_array) {
      $name =~ s/\.[0-9]*$//;
      $all_alignments->{$name}++;
    }
  }

  foreach my $source (keys %{$all_evidence}) {
    $support->log("\n\nStudying source $source:");
    my $data = $all_evidence->{$source};
    foreach my $type (keys %{$data}) {
      my $c = 0;
      my ($match,$no_match) = (0,0);
      $support->log("\nLooking at $source non matches for evidence type $type:\n",1);
      foreach my $rec (sort keys %{$all_evidence->{$source}{$type}}) {
	my ($acc,$tsi,$acc_ver) = split ':', $rec;
	if (exists ($all_alignments->{$acc})) {
	  $match++;
	}
	else {
	  $c++;
	  $no_match++;
	  $support->log("$c. $acc:$acc_ver ($tsi)\n",2);
	}
      }
      $support->log("$source $type: $match accessions match, $no_match accessions do not match to align_features\n",1);
    }
  }
}

### END ###
	
# finish log
$support->finish_log;

