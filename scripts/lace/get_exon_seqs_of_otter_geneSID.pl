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


use warnings;


### get_exon_seqs_of_otter_geneSID

use strict;
use Bio::Otter::Lace::Defaults;

my ($dataset, $cds_only, $all_exons, $flank_left, $flank_right, $infile);

my $help = sub { exec('perldoc', $0) };

Bio::Otter::Lace::Defaults::do_getopt(
    'ds|dataset=s' => \$dataset,      # eg, human or mouse or zebrafish
    'all-exons'    => \$all_exons,    # output seqs for all exons
    'cds-only'     => \$cds_only,     # output seqs CDSes only
    'left=i'       => \$flank_left,   # number of left flank bp
    'right=i'      => \$flank_right,  # number of right flank bp
    'file=s'       => \$infile        # file with gene stable id (one each line)
    );

$help->() unless ( $dataset and $flank_left and $flank_right and ($cds_only or $all_exons) and $infile);

my $client   = Bio::Otter::Lace::Defaults::make_Client();
my $dset     = $client->get_DataSet_by_name($dataset);
my $otter_db = $dset->get_cached_DBAdaptor;
my $sliceAd  = $otter_db->get_SliceAdaptor;
my $geneAd   = $otter_db->get_GeneAdaptor;
my $geneSID_list;

if ( $infile ){
  open my $fh, '<', $infile or die $!;
  while (<$fh>){
    chomp;
    push(@$geneSID_list, $_);
  }
}

foreach my $gsid ( @$geneSID_list ){
  my $gsidref = [$gsid];

  my $gene = $geneAd->fetch_by_stable_id($gsid);
  my $slice = $sliceAd->fetch_by_gene_stable_id( $gsid, ($flank_left + $flank_right) );

  print $gene->stable_id, ": ", scalar @{$gene->get_all_Transcripts}, " transcripts\n\n";

  # first get the longest transcript
  my ($len_trans, $trans);
  foreach my $t ( @{$gene->get_all_Transcripts} ) {
    $len_trans->{abs($t->end - $t->start) + 1} = $t;
  }

  $trans = $len_trans->{(sort {$a<=>$b} keys %$len_trans)[-1]};

  my $transSID = $trans->stable_id;

  if ( ! $trans->translation ) {
    print $trans->stable_id, ": no translation available\n";
  }
  else {
    if ( $cds_only) {
      my ($prot_seq, $prot_len) = sixty_cols($trans->translate->primary_seq->seq);
      my $protID = $trans->translation->stable_id;
      printf(">%s\t%s\t%d\n%s\n", $transSID, $protID, $prot_len, $prot_seq);

      print_exon_seq($transSID, 'CDS only', $trans, $gene, "get_all_translateable_Exons");
    }
  }
  if ( $all_exons ) {
    print_exon_seq($transSID, 'ALL exons', $trans, $gene, "get_all_Exons");
  }
}


#-----------------------------
#        subroutines
#-----------------------------

sub print_exon_seq {

  # $mode: 'CDS only' or 'ALL exons'
  my ($transSID, $mode, $trans, $gene, $method) = @_;

  print "[$transSID: $mode]\n";
  foreach my $exon ( @{$trans->$method} ) {

    next if $exon->stable_id =~ /^ENSMUSE/; # annotation errors

    my $header = $exon->stable_id."\t" .$gene->stable_id."\t".$gene->gene_info->name->name;

    if ( $flank_left and $flank_right ) {
      my ($flanked_seq, $new_len) = add_flank_seqs($exon, length($exon->seq->seq), $flank_left, $flank_right);
      printf(">%s\t%d\n%s\n", $header, $new_len, $flanked_seq);
    }
    else {
      my ($exon_seq, $ori_len) = sixty_cols($exon->seq->seq);
      printf(">%s\t%d\n%s\n", $header, $ori_len, $exon_seq);
    }
  }
  print "\n";

  return;
}

sub add_flank_seqs {
  my ($exon, $ori_len, $flank_left, $flank_right) = @_;

  $exon->start($exon->start - 100);
  $exon->end($exon->end + 100 );

  return format_seq($ori_len, $exon->seq->seq, $flank_left, $flank_right);
}

sub format_seq {

  my ($ori_len, $seq, $flant_left, $flank_right) = @_;

  $seq = join('', split(/\n/, $seq));

  my $flant_left_seq  = lc( substr($seq, 0, $flant_left) );
  my $flank_right_seq = lc( substr($seq, -$flank_right, $flank_right) );

  my $mid_seq  = substr($seq, $flant_left, $ori_len);

  return sixty_cols($flant_left_seq . $mid_seq . $flank_right_seq);

}

sub sixty_cols {

  my $seq  = shift;
  my $ori_len = length($seq);
  my $format_seq;

  while ($seq =~ /(.{1,60})/g) {
    $format_seq .= $1 . "\n";
  }
  chomp $format_seq;

  return ($format_seq, $ori_len);
}

=head1 NAME - get_exon_seqs_of_otter_geneSID.pl

=head1 SYNOPSIS

eg, ./get_exon_seqs_of_otter_geneSID -ds human -cds-only -left 100 -right 100 -all-exons -file genelist_human


=head1 DESCRIPTION

Output individual exon sequence of a gene

-all-exons: including UTRs

-cds-only: CDSes

-left /-right: bp of flank (the flanking seqs are lowercased)

-file: filename with OTTIDs one per line

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

