#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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


use warnings;


### get_DNA_Protein_seqs_of_genes_in_fasta

use strict;
use Getopt::Long 'GetOptions';
use Bio::Otter::Lace::Defaults;

$| = 1;

my ($dataset, @sets, $vega);

my $help = sub { exec('perldoc', $0) };

Bio::Otter::Lace::Defaults::do_getopt(
    'ds|dataset=s' => \$dataset, # eg, human or mouse or zebrafish
    's|set=s@'     => \@sets,    # sequence set(s) to check
    'h|help'       => $help,
    'v|vega'       => \$vega,    # this flags vega_set_id > 0. If !$vega: check all datasets
    # for now, zebrafish defaults to !$vega
    ) or $help->();               # plus default options
$help->() unless ( $dataset );
$help->() if ( $vega and @sets );                                  # vega option does all vega sets


my $client    = Bio::Otter::Lace::Defaults::make_Client();         # Bio::Otter::Lace::Client
my $dset      = $client->get_DataSet_by_name($dataset);            # Bio::Otter::Lace::DataSet
my $otter_db  = $dset->get_cached_DBAdaptor;                       # Bio::EnsEMBL::Containerr
my $geneAd    = $otter_db->get_GeneAdaptor;                        # Bio::Otter::AnnotatedGeneAdaptor

my $date = `date +%Y%m%d`; chomp $date;
my $gene_info_of_trans    = {};
my $gene_info_of_trans_AA = {};

# loop thru all assembly types to fetch all annotated genes in it on otter
if ( @sets ) {

  foreach my $set ( @sets ) {

    print "\nExamining gene IDs on '$set'\n";

    my $seqSet    = $dset->get_SequenceSet_by_name($set);
    $dset->fetch_all_CloneSequences_for_SequenceSet($seqSet);

    my $chrom;
    $chrom = $seqSet->CloneSequence_list()->[0]->chromosome;

    my $sliceAd = $otter_db->get_SliceAdaptor;
    my $slice   = $sliceAd->fetch_by_chr_name($chrom->name);

    my $latest_gene_id = $geneAd->list_current_dbIDs_for_Slice($slice);

    my ($coding, $transcripts, $pseudos) = get_latest_trans_or_prot_seq($latest_gene_id, $slice);

    foreach ($coding, $transcripts, $pseudos){
      output_sequences($_, $set);
    }
  }
}


#############################################################
#                   s u b r o u t i n e s
#############################################################


sub get_latest_trans_or_prot_seq {

  my ($latest_gene_id, $slice) = @_;
  my ($coding, $transcripts, $pseudos);
  my $done;

  foreach my $id ( @$latest_gene_id ) {
    $done++;
    print STDOUT ".";
    print STDOUT "\t$done\n"  if $done % 100 == 0;

    # transform contig coords of a gene into chrom. coords
    my $gene;
    $gene = $geneAd->fetch_by_dbID($id)->transform($slice) if $slice;
    $gene = $geneAd->fetch_by_dbID($id)                    if !$slice;

    # always filter out gene type = "obsolete"
    next if $gene->type eq "obsolete";

    my $trans_list = $gene->get_all_Transcripts;

    # group transcripts into coding, Pseudogene and the rest;

    foreach my $trans ( @$trans_list ) {

      my $geneTYPE   = $gene->type;
      my $geneID     = $gene->stable_id;
      my $geneNAME   = $gene->gene_info->name->name;
      my $geneDESC   = $gene->description;
      my $transID    = $trans->transcript_info->transcript_stable_id;
      my $transNAME  = $trans->transcript_info->name;
      my $transCLASS = $trans->type;

      if ( $trans->translation ){
        my $protID  = $trans->translation->stable_id;

        push(@{$gene_info_of_trans_AA->{$trans}}, "$transID | GENE_ID $geneID | GENE_TYPE $geneTYPE | SYMBOL $geneNAME | TRANS_NAME $transNAME | TRANS_CLASS $transCLASS | PROT_ID $protID | DESC $geneDESC");
      }

      push(@{$gene_info_of_trans->{$trans}}, "$transID | GENE_ID $geneID | GENE_TYPE $geneTYPE | SYMBOL $geneNAME | TRANS_NAME $transNAME | TRANS_CLASS $transCLASS | DESC $geneDESC");

      next if $trans->transcript_info->class->name eq "Transposon";

      if ( $trans->transcript_info->class->name eq "Coding" ){
              # warn $trans->transcript_info->transcript_stable_id if $gene_sid eq 'OTTHUMG00000024196';
        push( @$coding, $trans );
      }
      elsif ( $trans->transcript_info->class->name =~ /pseudogene/i ){
        push( @$pseudos, $trans );
      }
      else {
        push( @$transcripts, $trans );
      }
    }
  }
  print STDOUT "\t$done\n";
  return $coding, $transcripts, $pseudos;
}


sub output_sequences {

  my ($trans_sets, $set) = @_;

  my ($protein, $fh);

  foreach my $t ( @$trans_sets ) {

    $set = $t->adaptor->db->assembly_type unless $set;

    my $exon_seqs;
    foreach my $exon ( @{$t->get_all_Exons} ){
      $exon_seqs .= $exon->seq->seq;
    }
    my $formatted_seq = sixty_cols($exon_seqs);

    my $trans_class = $t->transcript_info->class->name;
    my $filename;


#    if ( $trans_class eq "Coding" ) {
#      $filename = "Coding_genes_DNA_".$date;
#    }

#    elsif ( $trans_class =~ /pseudogene/i ) {
#      $filename = "Pseudogenes_DNA_".$date;
#    }
#    else {
#      $filename = "Transcripts_DNA_".$date;
#    }

    if ( $trans_class =~ /pseudogene/i ) {
      $filename = "Pseudogenes_DNA_".$date;
    }
    else {
      $filename = $trans_class."_genes_DNA_".$date;
    }


    open($fh, '>>', $filename) or die $!;
    print $fh ">@{$gene_info_of_trans->{$t}}\n";
    print $fh $formatted_seq, "\n\n";

    if ( $trans_class eq "Coding" ) {
      # print also prtein seq to a separate file for conding genes

      $filename = "Coding_genes_AA_".$date;
      open($fh, '>>', $filename) or die $!;

      # looks like some genes can be dubious due to incomplete annotation
      # eg, coding gene but its transcript does not have translation
      if ( exists $gene_info_of_trans_AA->{$t} ){
        print $fh ">@{$gene_info_of_trans_AA->{$t}}\n";
        my $protein = sixty_cols($t->translate->primary_seq->seq);
        print $fh $protein, "\n";
      }
      else {
        my $gene = $geneAd->fetch_by_transcript_id($t->dbID);
        printf("%s (%s) %s", $t->transcript_info->transcript_stable_id, $gene->stable_id, " has no associated translation\n");
      }
    }
  }

  return;
}

sub sixty_cols {

  my $seq  = shift;
  my $format_seq;

  while ($seq =~ /(.{1,60})/g) {
    $format_seq .= $1 . "\n";
  }
  return $format_seq;
}


__END__

=head1 NAME - get_DNA_Protein_seqs_of_genes_in_fasta.pl

=head1 SYNOPSIS

get_DNA_Protein_seqs_of_genes_in_fasta -dataset <dataset> -set <assembly_type>


=head1 DESCRIPTION

output DNA/Protein sequence of each splice variant of a gene in fasta format


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

