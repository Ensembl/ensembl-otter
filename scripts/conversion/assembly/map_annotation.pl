#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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

map_annotation.pl - map features from one assembly onto another

=head1 SYNOPSIS

map_annotation.pl [options]

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

    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host
                                        HOST
    --evegaport=PORT                    use ensembl-vega (target) database port
                                        PORT
    --evegauser=USER                    use ensembl-vega (target) database
                                        username USER
    --evegapass=PASS                    use ensembl-vega (target) database
                                        passwort PASS
    --chromosomes, --chr=LIST           only process LIST chromosomes
    --prune                             delete results from previous runs of
                                        this script first
    --logic_names=LIST                  restrict transfer to gene logic_names
    --for_web                           remove artifact genes and transcripts
    --keep_overlap_evi                  keep supporting evidence alignments that
                                        overlap the edge of the seq_region (ie PATCH)
                                        optional, default is to delete them

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

Given a database with a mapping between two different assemblies of the same
genome, this script transfers features from one assembly to the other.

Features transfer include:

    - genes/transcripts/exons/translations
    - xrefs
    - supporting features and associated dna/protein_align_features
    - protein features

Currently, only complete transfers are considered. This is the easiest way to
ensure that the resulting gene structures are identical to the original ones.
For future release, there are plans to store incomplete matches by using the
Ensembl API's SeqEdit facilities.

Genes on PATCHES (non_ref top level seq_regions in Vega) are transferred by assigning
them to a different seq_region rather than using the assembly mapper and creating new
objects. There have been problems with some of these not transferring because
transcript_supporting_feature (not supporting_feature, these are always removed)
alignments overlapping the edge of the patch have failed to transfer. Once this is fixed
then keep_overlap_evi option to keep them

Genes transferred can be restricted on logic_name using the --logic_names
option. Used for mouse (-logic_names otter,otter_external).

Look in the logs for 'Set coordinates' and check exon coordinates of any examples
- untested code.

=head1 RELATED SCRIPTS

The whole Ensembl-vega database production process is done by these scripts:

    ensembl-otter/scripts/conversion/assembly/make_ensembl_vega_db.pl
    ensembl-otter/scripts/conversion/assembly/map_annotation.pl
    ensembl-otter/scripts/conversion/assembly/finish_ensembl_vega_db.pl

See documention in the respective script for more information.


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>
Based on code originally wrote by Graham McVicker and Patrick Meidl

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
  unshift(@INC, "./modules");
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/sanger-plugins/vega/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::Analysis;
use InterimTranscript;
use InterimExon;
use Deletion;
use Transcript;
use Gene;

use Data::Dumper;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
### PARALLEL # $support ###

#$SIG{INT}= 'do_stats_logging';      # signal handler for Ctrl-C, i.e. will call sub do_stats_logging

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'assembly=s',
  'evegahost=s',
  'evegaport=s',
  'evegauser=s',
  'evegapass=s',
  'evegadbname=s',
  'ensemblassembly=s',
  'chromosomes|chr=s@',
  'logic_names=s@',
  'prune',
  'keep_overlap_evi',
  'for_web',
);
$support->allowed_params(
  $support->get_common_params,
  'assembly',
  'evegahost',
  'evegaport',
  'evegauser',
  'evegapass',
  'evegadbname',
  'ensemblassembly',
  'chromosomes',
  'logic_names',
  'prune',
  'keep_overlap_evi',
  'for_web',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->comma_to_list('logic_names');

#set logic_names if not already
if ($support->param('dbname') =~ /[mus_musculus|homo_sapiens]/) {
  unless ($support->param('logic_names')) {
    $support->param('logic_names','otter');
  }
}
my @logic_names = ( $support->param('logic_names'));

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $V_dba = $support->get_database('core');
my $V_dbh = $V_dba->dbc->db_handle;
my $V_sa = $V_dba->get_SliceAdaptor;
my $V_ga = $V_dba->get_GeneAdaptor;
my $V_pfa = $V_dba->get_ProteinFeatureAdaptor;
my $E_dba = $support->get_database('evega', 'evega');
my $E_dbh = $E_dba->dbc->db_handle;
my $E_sa = $E_dba->get_SliceAdaptor;
my $E_ga = $E_dba->get_GeneAdaptor;
my $E_ta = $E_dba->get_TranscriptAdaptor;
my $E_pfa = $E_dba->get_ProteinFeatureAdaptor;
my $cs_adaptor = $E_dba->get_CoordSystemAdaptor;
my $asmap_adaptor = $E_dba->get_AssemblyMapperAdaptor;

my $E_cs = $cs_adaptor->fetch_by_name('chromosome',$support->param('ensemblassembly')) || $support->log_error("Can't retrieve adapator for coord_system ".$support->param('ensemblassembly')."\n");
my $V_cs = $cs_adaptor->fetch_by_name('chromosome',$support->param('assembly')) || $support->log_error("Can't retrieve adapator for coord_system ".$support->param('assembly')."\n");

# get assembly mapper
my $mapper_chr = $asmap_adaptor->fetch_by_CoordSystems($E_cs, $V_cs);
$mapper_chr->max_pair_count( 6_000_000 );
$mapper_chr->register_all;

sub map_it {
  my ($mapper,$f) = @_;
 
  if($mapper) { 
    return $mapper->map(
      $f->seq_region_name,
      $f->seq_region_start,
      $f->seq_region_end,
      $f->seq_region_strand,
      $V_cs,
    );
  } else {
    my $slice = $E_sa->fetch_by_region(undef,$f->slice->seq_region_name,undef,undef,undef,$E_cs->version);
    return (Bio::EnsEMBL::Mapper::Coordinate->new($slice->get_seq_region_id,$f->seq_region_start,$f->seq_region_end,$f->strand,$E_cs));
  }
}

# if desired, delete entries from previous runs of this script
if ($support->param('prune') && $support->user_proceed("Do you want to delete all entries from previous runs of this script?")) {
  $support->log("Deleting db entries from previous runs of this script...\n");
  $E_dbh->do(qq(DELETE FROM analysis));
  $E_dbh->do(qq(DELETE FROM dna_align_feature));
  $E_dbh->do(qq(DELETE FROM exon));
  $E_dbh->do(qq(DELETE FROM exon_transcript));
  $E_dbh->do(qq(DELETE FROM gene));
  $E_dbh->do(qq(DELETE FROM gene_attrib));
  $E_dbh->do(qq(DELETE FROM object_xref));
  $E_dbh->do(qq(DELETE FROM protein_align_feature));
  $E_dbh->do(qq(DELETE FROM protein_feature));
  $E_dbh->do(qq(DELETE FROM transcript_supporting_feature));
  $E_dbh->do(qq(DELETE FROM supporting_feature));
  $E_dbh->do(qq(DELETE FROM transcript));
  $E_dbh->do(qq(DELETE FROM transcript_attrib));
  $E_dbh->do(qq(DELETE FROM translation));
  $E_dbh->do(qq(DELETE FROM translation_attrib));
  $E_dbh->do(qq(DELETE x
                  FROM xref x, external_db ed
                  WHERE x.external_db_id = ed.external_db_id
                  AND ed.db_name NOT IN ('Interpro')
     ));
  $support->log("Done.\n");
}

my (%stat_hash,%trans_numbers);

# loop over chromosomes
$support->log("Looping over chromosomes...\n");
my $V_chrlength = $support->get_chrlength($E_dba, $support->param('assembly'),'chromosome',1);
my $E_chrlength = {
  %{$support->get_chrlength($E_dba, $support->param('ensemblassembly'),'chromosome',1,[])},
  %{$support->get_chrlength($E_dba, $support->param('ensemblassembly'),'supercontig',1,[])},
};
my $ensembl_chr_map = $support->get_ensembl_chr_mapping($V_dba, $support->param('assembly'));

### PRE # # %stat_hash %trans_numbers ###

my @chrs = $support->sort_chromosomes($V_chrlength);

### SIZE # (\d+|X|Y) # 1 ###
### SIZE # # 0.05 ###
### RUN # @chrs ###

CHROM:
foreach my $V_chr (@chrs) {

#  next unless ($V_chr =~ /HSCHR5_2_CTG1_1|HSCHR6_1_CTG2/);

  $support->log_stamped("Chromosome $V_chr...\n");

  # skip non-ensembl chromosomes
  my $E_chr = $ensembl_chr_map->{$V_chr};
  unless ($E_chrlength->{$E_chr}) {
    $support->log_warning("Ensembl chromosome equivalent to $V_chr not found. Skipping.\n", 1);
    next;
  }

  # fetch chromosome slices
  my $V_slice = $V_sa->fetch_by_region('chromosome', $V_chr, undef, undef,
				       undef, $support->param('assembly'));
  my $mapper;
  my $E_slice = $E_sa->fetch_by_region('chromosome', $E_chr, undef, undef,
				       undef, $support->param('ensemblassembly'));
  if($E_slice) {
    $mapper = $mapper_chr;
  } else {
    $E_slice = $E_sa->fetch_by_region('supercontig', $E_chr, undef, undef,
              undef, $support->param('ensemblassembly'));
  }

  if (! $E_slice ) {
    $support->log_warning("Can't get an Ensembl chromosome for $E_chr - have you used the right ensembl db as a template ?\n");
  }

  my ($genes) = $support->get_unique_genes($V_slice,$V_dba);
  $support->log("Looping over ".scalar(@$genes)." genes...\n", 1);

 GENE:
  foreach my $gene (@{ $genes }) {
    my $gsi = $gene->stable_id;

    #uncomment line here to debug overlapping supporting evidence (-verbose -chr HG185_PATCH)
#    next unless ($gsi =~ /OTTHUMG00000174590|OTTHUMG00000174616|OTTHUMG00000174807/);
#    next unless $gsi eq 'OTTDARG00000036477';

    my $ln = $gene->analysis->logic_name;
    my $name = $gene->display_xref->display_id;
    if ($support->param('logic_names')) {
      unless (grep {$ln eq $_} @logic_names) {
	$support->log_verbose("Skipping gene $gsi/$name (logic_name $ln)\n",2);
	next GENE;
      }
    }
    if ( $support->param('for_web') && ( $gene->biotype =~ /artifact/ ) ) {
	$support->log("Gene: ".$gene->stable_id." skipping because of its biotype (".$gene->biotype . ")\n", 2);
	next GENE;
      }
    $support->log("Gene $gsi/$name (logic_name $ln)\n", 1);

    #commented out this whole chunk so all genes are mapped in the same way, Patch or No Patch
    #leave the call in though in case things change

    #PATCH genes are identified as being on non-reference slices...
#    if ( ! $V_slice->is_reference() and ! $support->is_haplotype($V_slice,$V_dba) ) {
#      &transfer_vega_patch_gene($gene,$V_chr);
#      next GENE;
#    }

    #All other genes
    my $transcripts = $gene->get_all_Transcripts;
    my (@finished, %all_protein_features, $failed_transcripts);
    my $c = 0;
  TRANS:
    foreach my $transcript (@{ $transcripts }) {
      my $tsi = $transcript->stable_id;
      if ( $support->param('for_web') && ($transcript->biotype =~ /artifact/) ) {
        $support->log("Transcript: $tsi skipping because of its biotype (" . $transcript->biotype. ")\n", 2);
        $failed_transcripts->{$tsi}{'biotype'} = $transcript->biotype;
        push @{$failed_transcripts->{$tsi}{'details'}}, {'reason' => 'disallowed biotype'};
        next TRANS;
      }

      my ($interim_transcript,$failed_transcript) = transfer_transcript($transcript, $mapper, $V_cs, $V_pfa, $E_slice);
      if (%$failed_transcript) {
        $failed_transcripts->{$tsi}{'biotype'} = $transcript->biotype;
        push @{$failed_transcripts->{$tsi}{'details'}}, $failed_transcript;
      }
      $c++;
      my ($finished_transcripts, $protein_features, $another_failed_transcript) = create_transcripts($interim_transcript, $E_sa, $gsi);
      if (%$another_failed_transcript) {
        $failed_transcripts->{$tsi}{'biotype'} = $transcript->biotype;
        push @{$failed_transcripts->{$tsi}{'details'}}, $another_failed_transcript;
      }

      # set the translation stable identifier on the finished transcripts
      foreach my $tr (@{ $finished_transcripts }) {
	if ($tr->translation && $transcript->translation) {
	  $tr->translation->stable_id($transcript->translation->stable_id);
	  $tr->translation->version($transcript->translation->version);
	  $tr->translation->created_date($transcript->translation->created_date);
	  $tr->translation->modified_date($transcript->translation->modified_date);
	}
      }
			
      push @finished, @$finished_transcripts;
      map { $all_protein_features{$_} = $protein_features->{$_} }
	keys %{ $protein_features || {} };
    }

    # if there are no finished transcripts, count this gene as being NOT transfered
    my $num_finished_t= @finished;
    if(! $num_finished_t){
      push @{$stat_hash{$V_chr}->{'failed'}}, [$gene->stable_id,$gene->seq_region_start,$gene->seq_region_end];
      next GENE;
    }

    #make a note of the number of transcripts per gene
    $trans_numbers{$gsi}->{'vega'} = scalar(@{$transcripts});
    $trans_numbers{$gsi}->{'evega'} = $num_finished_t;

    #count gene and transcript if it's been transferred
    $stat_hash{$V_chr}->{'genes'}++;
    $stat_hash{$V_chr}->{'transcripts'} += $c;

    unless ($support->param('dry_run')) {
      Gene::store_gene($support, $E_slice, $E_ga, $E_ta, $E_pfa, $gene,
		       \@finished, \%all_protein_features, $failed_transcripts);
    }
  }
  $support->log("Done with chromosome $V_chr.\n\n", 1);
}

### POST ###

#see if any transcripts / gene are different
foreach my $gsi (keys %trans_numbers) {
  if ($trans_numbers{$gsi}->{'vega'} != $trans_numbers{$gsi}->{'evega'}) {
    my $v_num = $trans_numbers{$gsi}->{'vega'};
    my $e_num = $trans_numbers{$gsi}->{'evega'};
    $support->log("There are different numbers of transcripts for gene $gsi in vega ($v_num) and ensembl_vega ($e_num)\n");
  }
}

# write out to statslog file
do_stats_logging();

### END ###

# finish logfile
$support->finish_log;

### END main


=head2 transfer_vega_patch_gene

  Arg[1]      : Bio::Vega::Gene - Vega source gene
  Arg[2]      : Bio::Vega::Slice - Vega destination chromosome
  Arg[3]      : arrayref of attrib_type.codes
  Description : Transforms a Loutre gene into a Vega gene
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub transfer_vega_patch_gene {
  my ($vgene,$V_chr) = @_;
  my $gsi = $vgene->stable_id;
  my $v_gene_slice = $vgene->slice;

  my $slice_start = $v_gene_slice->start;
  my $slice_end   = $v_gene_slice->end;

  if(!$v_gene_slice) {		
    $support->log_warning("Couldn't fetch vega gene slice\n");
    return 0;
  }
  my ($min_start,$max_end);
  my $ev_gene_slice = $E_sa->fetch_by_region(
    $v_gene_slice->coord_system()->name(),
    $v_gene_slice->seq_region_name,
    $slice_start,
    $slice_end,
    undef,
    $support->param('ensemblassembly')
  );

  # using this rather than the above allows transfer of overlapping transcript supporting evidence (although supporting_evidence must still be removed)
  # however gene coords are then relative to the patch rather than in context
#  my $ev_gene_slice = $E_sa->fetch_by_region(
#    $v_gene_slice->coord_system()->name(),
#    $v_gene_slice->seq_region_name,
#    $slice_start,
#    $slice_end,
#    undef,
#    $support->param('ensemblassembly')
# );

  if(!$ev_gene_slice) {
    $support->log_warning("Couldn't fetch ensembl_vega gene slice\n");
    return 0;
  }

  if(!@{$vgene->get_all_Transcripts}){
    $support->log_warning("No transcripts for Vega gene ".$vgene->dbID."\n");
    return 0;
  }
  my $found_trans     = 0;
  my $needs_updating = 0;
  my %artifact_ids;
  my @transcripts = @{$vgene->get_all_Transcripts};

  $support->log_verbose("Vega gene $gsi in vega has coords of ".$vgene->seq_region_start.":".$vgene->seq_region_end."\n",3);

  my $c = 0;
 TRANS:
  foreach my $transcript (@transcripts){
    if ( $support->param('for_web') && $transcript->biotype =~ /artifact/) {
      $support->log("Transcript: ".$transcript->stable_id." skipped because of its biotype (" . $transcript->biotype .")\n", 2);
      $needs_updating = 1;
      $artifact_ids{$transcript->stable_id} = 1;
      next TRANS;
    }

    if($transcript->translation){
      $transcript->translation;
    }
    $transcript->stable_id;

    $support->log("Will transfer ".$transcript->stable_id."\n",2);
    $found_trans = 1;

    my @tsfs = @{$transcript->get_all_supporting_features};
    unless ( $support->param('keep_overlap_evi')) {
    TSF:
      foreach my $sf (@tsfs) {
        #delete transcript supporting_features that lie outside the slice
        if ($sf->seq_region_start < $slice_start || $sf->seq_region_end > $slice_end) {
          &delete_supporting_feature('transcript',$transcript,$sf->dbID,$sf->display_id);
          next TSF;
        }
      }
    }

    my @exons= @{$transcript->get_all_Exons};
    foreach my $exon (@exons) {
      my @esfs = @{$exon->get_all_supporting_features};
    SF:
      foreach my $sf (@esfs) {
        #delete supporting features that lie outside the slice
        if ($sf->seq_region_start < $slice_start || $sf->seq_region_end > $slice_end) {
          &delete_supporting_feature('exon',$exon,$sf->dbID,$sf->display_id);
          next SF;
        }
      }
      $exon->slice($ev_gene_slice);
    }
    $transcript->slice($ev_gene_slice);
  }
  $vgene->slice($ev_gene_slice);

  #if we found a transcript to ignore then the gene start/stop need updating, and we need to delete the transcript before storing the gene
  my $trans_c = scalar(@transcripts);
  if ($needs_updating){
    foreach my $transcript (@transcripts){
      if ($artifact_ids{$transcript->stable_id}) {
        $trans_c--;
        &remove_Transcript($vgene,$transcript->stable_id);
      }
      else {
        if ($transcript->start < $vgene->start){
          $vgene->start=$transcript->start;
        }
        if ($transcript->end > $vgene->end){
          $vgene->end=$transcript->end;
        }
      }
    }
  }

  #add xrefs to Vega stable IDS (needed by genebuilders)
  $vgene->get_all_DBLinks; #need to lazy load existing ones otherwise they get overwritten by the below
  $vgene->add_DBEntry(Bio::EnsEMBL::DBEntry->new
      (-primary_id => $vgene->stable_id,
       -version    => $vgene->version,
       -dbname     => 'Vega_gene',
       -release    => 1,
       -display_id => $vgene->stable_id,
       -info_text  => 'Added during ensembl-vega production'));

  Gene::create_vega_xrefs(\@transcripts);

  #make a note of the number of transcripts per gene
  $trans_numbers{$gsi}->{'vega'} = scalar(@transcripts);
  $trans_numbers{$gsi}->{'evega'} = $trans_c;

  #count gene and transcript if it's been transferred
  $stat_hash{$V_chr}->{'genes'}++;
  $stat_hash{$V_chr}->{'transcripts'} += $trans_c;

  $support->log_verbose("Ensembl-vega gene $gsi has coords of ".$vgene->seq_region_start.":".$vgene->seq_region_end."\n",3);

  if (! $support->param('dry_run')) {
    my $dbID;
    if (eval { $dbID = $E_ga->store($vgene); 1 } ) {
      $support->log("Stored gene ".$vgene->stable_id." ($dbID)\n",2);
      return 1;
    }
    else {
      $support->log_warning("Failed to store gene ".$vgene->stable_id."\n",2);
      warn $@ if $@;
      return 0;
    }
  }
  else {
    return 0;
  }
}

sub delete_supporting_feature {
  my ($type,$obj,$id) = @_;
  my $sfs = $obj->get_all_supporting_features;
  for (my $i = 0; $i < scalar(@{$sfs}); $i++) {
    my $sf = $sfs->[$i];
    if ($sf->dbID == $id) {
      $support->log("Removing $type supporting_feature ".$sf->display_id." (".$sf->dbID.") from ".$obj->stable_id."\n",3);
      splice(@{$sfs}, $i, 1);
    }
  }
}

sub remove_Transcript {
  my ($gene, $stable_id) = @_;
  my $transcripts = $gene->get_all_Transcripts();
  for(my $i = 0; $i < scalar(@{$transcripts}); $i++) {
    my $t = $transcripts->[$i];
    if($t->stable_id() eq $stable_id) {
      $support->log("Removing ".$t->stable_id." from list of transcripts that are going to be transferred\n",3);
      splice(@{$transcripts}, $i, 1);
    }
  }
}

=head2 transfer_transcript

  Arg[1]      : Bio::EnsEMBL::Transcript $transcript - Vega source transcript
  Arg[2]      : Bio::EnsEMBL::ChainedAssemblyMapper $mapper - assembly mappers
  Arg[3]      : Bio::EnsEMBL::CoordSystem $V_cs - Vega coordinate system
  Arg[4]      : Bio::EnsEMBL::ProteinFeatureAdaptor $V_pfa - Vega protein
                feature adaptor
  Arg[5]      : Bio::EnsEMBL::Slice $slice - Ensembl slice
  Description : This subroutine takes a Vega transcript and transfers it (and
                all associated features) to the Ensembl assembly.
  Return type : InterimTranscript - the interim transcript object representing
                the transfered transcript
  Exceptions  : none
  Caller      : internal

=cut

sub transfer_transcript {
  my $transcript = shift;
  my $mapper = shift;
  my $V_cs = shift;
  my $V_pfa = shift;
  my $E_slice = shift;

  my $tsi = $transcript->stable_id;

  $support->log_verbose("Transcript: $tsi\n", 3);

  my $failed_transcript = {};

  my $V_exons = $transcript->get_all_Exons;
  my $E_cdna_pos = 0;
  my $cdna_exon_start = 1;

  my $E_transcript = InterimTranscript->new;

  $E_transcript->stable_id($tsi);
  $E_transcript->version($transcript->version);
  $E_transcript->biotype($transcript->biotype);
  $E_transcript->status($transcript->status);
  $E_transcript->description($transcript->description);
  $E_transcript->created_date($transcript->created_date);
  $E_transcript->modified_date($transcript->modified_date);
  $E_transcript->cdna_coding_start($transcript->cdna_coding_start);
  $E_transcript->cdna_coding_end($transcript->cdna_coding_end);
  $E_transcript->transcript_attribs($transcript->get_all_Attributes);
  $E_transcript->analysis($transcript->analysis);

  # transcript supporting evidence
  foreach my $sf (@{ $transcript->get_all_supporting_features }) {
    # map coordinates
    my @coords = map_it($mapper,$sf);
    if (@coords == 1) {
      my $c = $coords[0];
      unless ($c->isa('Bio::EnsEMBL::Mapper::Gap')) {
	$sf->start($c->start);
	$sf->end($c->end);
	$sf->strand($c->strand);
	$sf->slice($E_slice);
	$E_transcript->add_TranscriptSupportingFeature($sf);
      }
    }
  }

  # protein features
  if (defined($transcript->translation)) {
    $E_transcript->add_ProteinFeatures(@{ $V_pfa->fetch_all_by_translation_id($transcript->translation->dbID) });
  }

  my @E_exons;

 EXON:
  foreach my $V_exon (@{ $V_exons }) {
    $support->log_verbose("Exon: " . $V_exon->stable_id . " chr=" .
			    $V_exon->slice->seq_region_name . " start=".
			      $V_exon->seq_region_start."\n", 4);

    my $E_exon = InterimExon->new;
    $E_exon->stable_id($V_exon->stable_id);
    $E_exon->version($V_exon->version);
    $E_exon->created_date($V_exon->created_date);
    $E_exon->modified_date($V_exon->modified_date);
    $E_exon->cdna_start($cdna_exon_start);
    $E_exon->start_phase($V_exon->phase);
    $E_exon->end_phase($V_exon->end_phase);

    # supporting evidence
    foreach my $sf (@{ $V_exon->get_all_supporting_features }) {
      # map coordinates
      my @coords = map_it($mapper,$sf);
      if (@coords == 1) {
	my $c = $coords[0];
	unless ($c->isa('Bio::EnsEMBL::Mapper::Gap')) {
	  $sf->start($c->start);
	  $sf->end($c->end);
	  $sf->strand($c->strand);
	  $sf->slice($E_slice);
	  $E_exon->add_SupportingFeature($sf);
	}
      }
    }

    # map exon coordinates
    my @coords = map_it($mapper,$V_exon);

    if (@coords == 1) {
      my $c = $coords[0];

      if ($c->isa('Bio::EnsEMBL::Mapper::Gap')) {
	#
	# Case 1: Complete failure to map exon
	#
        if ($support->param('verbose')) {
          $support->log_warning("Reason: Complete failure to transfer exon ".$V_exon->stable_id."\n",4);
        }
        $failed_transcript = {
          'reason'    => 'non mapped exon',
          'exon_id'   => $V_exon->stable_id};
	$E_exon->fail(1);
      }
      else {
	#
	# Case 2: Exon mapped perfectly
	#
	$E_exon->start($c->start);
	$E_exon->end($c->end);
	$E_exon->strand($c->strand);
	$E_exon->seq_region($c->id);

	$E_exon->cdna_start($cdna_exon_start);
	$E_exon->cdna_end($cdna_exon_start + $E_exon->length - 1);
	$E_cdna_pos += $c->length;
      }
    }
    else {
      my ($start,$end,$strand,$seq_region);
      my $gap = 0;	
      foreach my $c (@coords) {
      #
      # Case 3 : Exon mapped partially
      #
	if ($c->isa('Bio::EnsEMBL::Mapper::Gap')) {
	  $E_exon->fail(1);
          if ($support->param('verbose')) {
            $support->log("Reason: Exon ".$V_exon->stable_id." mapping has a gap\n",4);
          }
	  $gap = 1;
          $failed_transcript = {
            'reason'    => 'exon maps to gap',
            'exon_id'   => $V_exon->stable_id};
	  last;
	}
      }
      #
      # Case 4 : Multiple mappings for exon, but no gaps
      #
      unless ($gap) {
	my ($last_end);
	foreach my $c (sort {$a->start <=> $b->start} @coords) {
	  if ($last_end) {
	    if ($c->start != $last_end) {
	      $E_exon->fail(1);
              if ($support->param('verbose')) {
                $support->log("Reason: Exon ".$V_exon->stable_id." mapping has a mismatch in coords\n",4);
              }
              $failed_transcript = {
                'reason'    => 'exon coord mismatch',
                'exon_id'   => $V_exon->stable_id};
	      last;
	    }
	  }
	  $start = ! $start ? $c->start
	           : $start > $c->start ? $c->start
	           : $start;
	  $end = ! $end ? $c->end
	         : $end < $c->end ? $c->end
	         : $end;
	  $strand = $c->strand;
	  $seq_region = $c->id;
	  $last_end = $c->end;
	}
	
	$E_exon->start($start);
	$E_exon->end($end);
	$E_exon->strand($strand);
	$E_exon->seq_region($seq_region);

	$E_exon->cdna_start($cdna_exon_start);	
	my $length = $end-$start+1;
	$E_exon->cdna_end($cdna_exon_start + $length);
	$E_cdna_pos += $length+1;

	unless ($E_exon->fail) {
	  $support->log_warning("Set coordinates but this is untested code, please check\n");
	}

      }
    }
    $cdna_exon_start = $E_cdna_pos + 1;

    $E_transcript->add_Exon($E_exon);
  }
  return $E_transcript,$failed_transcript;
}



=head2 create_transcripts

  Arg[1]      : InterimTranscript $itranscript - an interim transcript object
  Arg[2]      : Bio::EnsEMBL::SliceAdaptor $E_sa - Ensembl slice adaptor
  Arg[3]      : Gene Stable ID (used for checking against curation)
  Description : Creates the actual transcripts from interim transcripts
  Return type : List of a listref of Bio::EnsEMBL::Transcripts and a hashref of
                protein features (keys: transcript_stable_id, values:
                Bio::Ensmembl::ProteinFeature)
  Exceptions  : none
  Caller      : internal

=cut

sub create_transcripts {
  my $itranscript   = shift;
  my $E_sa = shift;
  my $gsi = shift;

  # check the exons and split transcripts where exons are bad
  my ($itranscripts,$failed_transcript) = Transcript::check_iexons($support, $itranscript, $gsi);

  my @finished_transcripts;
  my %protein_features;
  foreach my $itrans (@{ $itranscripts }) {
    # if there are any exons left in this transcript add it to the list
    if (@{ $itrans->get_all_Exons }) {
      my ($tr, $pf) = Transcript::make_Transcript($support, $itrans, $E_sa);
      push @finished_transcripts, $tr;
      $protein_features{$tr->stable_id} = $pf;
    } else {
      $support->log("Transcript ". $itrans->stable_id . " has no exons left.\n", 3);
    }
  }
  return \@finished_transcripts, \%protein_features, $failed_transcript;
}

sub do_stats_logging{

  #writes the number of genes and transcripts processed to the log file
  #note: this can be called as an interrupt handler for ctrl-c,
  #so can also give current stats if script terminated

  my %failed;
  my $format = "%-20s%-10s%-10s\n";
  $support->log(sprintf($format,'Chromosome','Genes','Transcripts'));
  my $sep = '-'x41;
  $support->log("$sep\n");
  foreach my $chrom(sort keys %stat_hash){
    my $num_genes= $stat_hash{$chrom}->{'genes'};
    my $num_transcripts= $stat_hash{$chrom}->{'transcripts'};
    if(defined($stat_hash{$chrom}->{'failed'})){
      $failed{$chrom} = $stat_hash{$chrom}->{'failed'};
    }
    $support->log(sprintf($format,$chrom,$num_genes,$num_transcripts));
  }
  $support->log("\n");
  foreach my $failed_chr (keys %failed){
    my $no = scalar @{$failed{$failed_chr}};
    $support->log("$no genes not transferred on chromosome $failed_chr:\n");
    foreach my $g (@{$failed{$failed_chr}}) {
      $support->log("  ".$g->[0].": ".$g->[1]."-".$g->[2]."\n");
    }
  }
}
