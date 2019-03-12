#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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


# get_encode_stats_lite
# output stats of encode regions for Havana annotated genes and transcripts in specified time windows
# typical run: get_encode_stats_lite -ds human -time1 06-11-01 -time2 present

# Example output:
=pod
encode-ENm004-02     Total genes: 31
Gene_type                 (G   , T)
Artifact                  (0   , 0)
Expressed_pseudogene      (0   , 0)
Ig_Pseudogene_Segment     (0   , 0)
Ig_Segment                (0   , 0)
Known                     (18  , 132)
Novel_CDS                 (1   , 5)
Novel_Transcript          (4   , 4)
Polymorphic               (1   , 2)
Predicted_Gene            (0   , 0)
Processed_pseudogene      (2   , 2)
Pseudogene                (0   , 0)
Putative                  (5   , 6)
Retained_intron           (0   , 0)
TEC                       (0   , 0)
Transposon                (0   , 0)
Unprocessed_pseudogene    (0   , 0)
obsolete                  (0   , 0)
other                     (0   , 0)

Sum(31, 151) External(0, 0)
Trans_with_non_human_evidences(13) Trans_without_evidence_at_all(0)
=cut

use strict;
use Bio::Otter::Lace::Defaults;
use POSIX 'strftime';
use POSIX 'mktime';
use Time::Local;

$| = 1;

my ($dataset, @sets, $html_output, $cutoff_time_1, $cutoff_time_2);
my $encode_list = "/nfs/team71/analysis/jgrg/work/encode/encode_sets.list";

my $help = sub { exec('perldoc', $0) };

Bio::Otter::Lace::Defaults::do_getopt(
    'ds|dataset=s' => \$dataset, # eg, human or mouse or zebrafish
    'set=s'        => \@sets,
    'html=s'       => \$html_output,
    'h|help'       => $help,
    'time1=s'      => \$cutoff_time_1,
    'time2=s'      => \$cutoff_time_2,
    );

$cutoff_time_1 = get_timelocal($cutoff_time_1) if $cutoff_time_1;
$cutoff_time_2 = get_timelocal($cutoff_time_2) if $cutoff_time_2;

my $client   = Bio::Otter::Lace::Defaults::make_Client();
my $dset     = $client->get_DataSet_by_name($dataset);
my $otter_db = $dset->get_cached_DBAdaptor;
my $sliceAd  = $otter_db->get_SliceAdaptor;
my $geneAd   = $otter_db->get_GeneAdaptor;


# loop thru all assembly types to fetch all annotated genes in it on otter
unless ( @sets ){
  open(my $fh, '<', $encode_list) or die $!;
  while(<$fh>){
    chomp;
    push(@sets, $_);
  };
  close $fh;
}

my $wanted_gtypes = {
    Known                  => 'K',
    Novel_CDS              => 'NC',
    Novel_Transcript       => 'NT',
    Putative               => 'P',
    Processed_pseudogene   => 'PS',
    Unprocessed_pseudogene => 'UP',
    Artifact               => 'A',
    TEC                    => 'T',
    Expressed_pseudogene   => 'EP',
    Ig_Pseudogene_Segment  => 'IPS',
    Ig_Segment             => 'IS',
    Polymorphic            => 'PM',
    Predicted_Gene         => 'PG',
    other                  => 'OT',
    Pseudogene             => 'PSE',
    Retained_intron        => 'RI',
    Transposon             => 'T',
    obsolete               => 'OB'
};

my ( $annotated_gene_set_type,
     $total_genes_of_atype,
     $sum_annots_of_gtypes_of_atype,
     $total_annots_of_all_atype,
     $coding_locus_trans);

if ( @sets ) {

  my ($all_encode_gene, $all_encode_annot_g, $all_encode_annot_t);

  foreach my $set ( @sets ) {
    warn  $set, "\n";
    my ($total_gene_set);
    my ($trans_has_evi, $trans_no_evi );

    my $seqSet = $dset->get_SequenceSet_by_name($set);
    $dset->fetch_all_CloneSequences_for_SequenceSet($seqSet);
    my $chrom = $seqSet->CloneSequence_list()->[0]->chromosome;

    my $slice = $sliceAd->fetch_by_chr_name($chrom);
    my $latest_gene_ids = $geneAd->list_current_dbIDs_for_Slice($slice);

    foreach my $gid ( @$latest_gene_ids ){
      my $gene = $geneAd->fetch_by_dbID($gid);
      my $gtype = $gene->type;

      # exclude external/obsolete annotations
      next if  $gtype eq 'obsolete' or $gtype =~ /:/;
      #next unless $wanted_gtypes->{$gtype};

      if ( $cutoff_time_1 and $cutoff_time_2 ){
        if ( $gene->gene_info->timestamp <= $cutoff_time_2 and
             $gene->gene_info->timestamp >= $cutoff_time_1 ){

          $annotated_gene_set_type->{$set}->{$gtype}->{gene}++;
          $annotated_gene_set_type->{$set}->{$gtype}->{trans} +=
            scalar @{$gene->get_all_Transcripts};

          # all genes refer to all gene_types in the specified time window
          $total_gene_set++;
          $all_encode_gene++;

          if ( $gtype eq "Known" or $gtype eq "Novel_CDS" ){
            $coding_locus_trans->{$set}->{$gene->gene_info->name->name} = scalar @{$gene->get_all_Transcripts};
          }
          my $evi_count = count_trans_with_supporting_evi($gene);
          if ( $evi_count eq 'no_evi' ){
            $trans_no_evi++;
          }
          else {
            $trans_has_evi += $evi_count;
          }
        }
      }
      else {
        $annotated_gene_set_type->{$set}->{$gtype}->{gene}++;
        $annotated_gene_set_type->{$set}->{$gtype}->{trans} +=
          scalar @{$gene->get_all_Transcripts};
        if ( $gtype eq "Known" or $gtype eq "Novel_CDS" ){
          $coding_locus_trans->{$set}->{$gene->gene_info->name->name} = scalar @{$gene->get_all_Transcripts};
        }
      }
    }

    unless ( $cutoff_time_1 & $cutoff_time_2 ){
      $total_gene_set = scalar @$latest_gene_ids;
      $all_encode_gene += $total_gene_set;
    }

    printf("%-20s Total genes: %d\n", $set, $total_gene_set);
    $total_genes_of_atype->{$set} = $total_gene_set;

    printf("%-25s (%-4s, %s)\n", "Gene_type", "G", "T");
    my ($sum_gene, $sum_trans);

    my @present_types = keys %{$annotated_gene_set_type->{$set}};

    foreach my $gtype ( sort keys %$wanted_gtypes ){
      if ( grep {$_ eq $gtype} @present_types ){
        my $gene_count  = $annotated_gene_set_type->{$set}->{$gtype}->{gene};
        my $trans_count = $annotated_gene_set_type->{$set}->{$gtype}->{trans};
        printf("%-25s (%-4d, %d)\n", $gtype, $gene_count, $trans_count);

        $gene_count = 0 unless $gene_count;
        $trans_count = 0 unless $trans_count;

        $sum_gene += $gene_count;
        $sum_trans += $trans_count;
      }
      else {
        printf("%-25s (%-4d, %d)\n", $gtype, 0, 0);
      }
    }

    my ($excluded_sum_gene, $excluded_sum_trans);

    foreach my $type ( @present_types) {
      next if $type !~ /:/;
      my $gene_count  = $annotated_gene_set_type->{$set}->{$type}->{gene};
      my $trans_count = $annotated_gene_set_type->{$set}->{$type}->{trans};
      #printf("%s(%d, %d) ", $type, $gene_count, $trans_count);
      $excluded_sum_gene += $gene_count;
      $excluded_sum_trans += $trans_count;
    }

    $all_encode_annot_g += $sum_gene;
    $all_encode_annot_t += $sum_trans;

    printf("\n%s(%d, %d) %s(%d, %d)\n",
           "Sum", $sum_gene, $sum_trans,
           "External", $excluded_sum_gene, $excluded_sum_trans);

    $sum_annots_of_gtypes_of_atype->{$set}->{G}= $sum_gene;
    $sum_annots_of_gtypes_of_atype->{$set}->{T}= $sum_trans;

    $trans_no_evi = 0 unless $trans_no_evi;
    $trans_has_evi = 0 unless $trans_has_evi;
    #print "Trans_with_non_human_evidences(0) Trans_without_evidence_at_all($trans_no_evi)\n\n";\n\n";
    print "Trans_with_non_human_evidences($trans_has_evi) Trans_without_evidence_at_all($trans_no_evi)\n\n";
  }

  print "\nNumber of coding variants per coding locus:\n";
  foreach my $set ( sort keys %$coding_locus_trans ){
    print "$set: \n";
    foreach  my $gname ( keys %{$coding_locus_trans->{$set}} ){
      printf("%-20s %d\n", $gname, $coding_locus_trans->{$set}->{$gname} );
    }
  }
  print "\n";

  print "Total encode genes: $all_encode_gene\n";
  print "Total Havana annotated genes: $all_encode_annot_g\n";
  print "Total Havana annotated trans: $all_encode_annot_t\n";

  $total_annots_of_all_atype->{A} = $all_encode_gene;
  $total_annots_of_all_atype->{G} = $all_encode_annot_g;
  $total_annots_of_all_atype->{T} = $all_encode_annot_t;

}


# output html for 3 tables
output_html($annotated_gene_set_type, $sum_annots_of_gtypes_of_atype, $total_annots_of_all_atype, $coding_locus_trans, $html_output);

#------------------------------
#         subroutines
#------------------------------

sub get_timelocal {
  my $yymmdd = shift;
  my ($year, $mon, $day) = split(/-/, $yymmdd);

  $mon-- if $mon;

  # sec, min, hr, day, mon, year
  if ( $yymmdd eq "present" ){
    ($day,$mon,$year) = (localtime)[3..5];
    return timelocal(59,59,23,$day,$mon,$year);
  }

  return timelocal(0,0,0,$day,$mon,$year);
}


sub output_html {

  my ($annotated_gene_set_type, $sum_annots_of_gtypes_of_atype,
      $total_annots_of_all_atype, $coding_locus_trans, $html_output) = @_;

  my $top =<<'TOP';
<html>
<body>
TOP

  my $rows;

  #---------------------
  # table 1: code table
  #---------------------
  $rows .= $top;
  $rows .= qq{<span>Table 1: Gene type code</span>};
  $rows .= qq{<table border=1>};
  $rows .= qq{<tr><th>Code</th><th>Gene type</th>};
  my %code_2_gtype = reverse %$wanted_gtypes;
  foreach my $code ( sort keys %code_2_gtype ){
    $rows .= "<tr><td>$code</td><td>". $code_2_gtype{$code}."</td>";
  }
  $rows .= qq{</table><p>};

  #----------
  # table 2
  #----------

  $rows .= qq{<span>Table 2: Annotated <span style="color: green">genes</span>/<span style="color: magenta">transcripts</span> of current gene types</span>};
  $rows .= qq{<table border=1>};
  $rows .= qq{<tr><th>Assembly</th>};
  my $colspan = scalar keys %$wanted_gtypes;

  foreach my $gtype ( sort keys %$wanted_gtypes ){
    my $code = $wanted_gtypes->{$gtype};
    $rows .= qq{<th title=\"$gtype\">$code</th>};
  }

  $rows .= qq{<th>Sum</th>};

  foreach my $atype ( sort keys %{$annotated_gene_set_type} ) {
    $rows .= qq{<tr><td>$atype</td>};
    foreach my $gtype ( sort keys %{$annotated_gene_set_type->{$atype}} ) {
      my $gcount = $annotated_gene_set_type->{$atype}->{$gtype}->{gene};
      my $tcount = $annotated_gene_set_type->{$atype}->{$gtype}->{trans};

      if ( $wanted_gtypes->{$gtype} ){
        ( $gcount+$tcount != 0 )
          ? ($rows .= qq{<td><span style="color: green">$gcount</span> / <span style="color:magenta">$tcount</span></td>})
          : ( $rows .= qq{<td>&nbsp;</td>} );
      }
      else {
        $rows .= qq{<td>&nbsp;</td>};
      }
    }
    my $sumg = $sum_annots_of_gtypes_of_atype->{$atype}->{G};
    my $sumt = $sum_annots_of_gtypes_of_atype->{$atype}->{T};
    ( $sumg+$sumg != 0 )
      ? ($rows .= qq{<td><span style="color: green">$sumg</span> / <span style="color: magenta">$sumt</span></td>})
      : ( (scalar keys %{$annotated_gene_set_type->{$atype}} >= 1 )
           ? ( $rows .= qq{<td>&nbsp;</td>} )
           : ( $rows .= qq{<td colspan="$colspan">&nbsp;</td><td><span style="color: green">0</span> / <span style="color: magenta">0</td>} )
        );
  }
  $rows .= qq{</table><p>};

  #----------
  # table 3
  #----------
  $rows .= qq{<span>Table 3: Total number of genes vs annotated genes/transcripts</span>};
  $rows .= qq{<table border=1>};
  $rows .= qq{<tr><th>Total genes</th><th>Havana annotated genes</th><th>Havanna annotated trans</th>};
  my $all    = $total_annots_of_all_atype->{A};
  my $gcount = $total_annots_of_all_atype->{G};
  my $tcount = $total_annots_of_all_atype->{T};

  $rows .= qq{<tr><td>$all</td><td>$gcount</td><td>$tcount</td>};
  $rows .= qq{</table><p>};

  #----------
  # table 4
  #----------

  $rows .= qq{<span>Table 4: Number of coding variants of coding locus</span>};
  $rows .= qq{<table border=1>};

  foreach my $atype ( sort keys %$coding_locus_trans ) {
    my $rowspan = scalar keys %{$coding_locus_trans->{$atype}};
    $rows .= qq{<tr><th rowspan=$rowspan>$atype</th>};
    my $count;
    foreach my $locus ( sort keys %{$coding_locus_trans->{$atype}} ) {
      $count++;
      if ( $count == 1 ) {
        $rows .= "<th>$locus</th><td>".$coding_locus_trans->{$atype}->{$locus}."</td></tr>";
      } else {
        $rows .= "<tr><th>$locus</th><td>". $coding_locus_trans->{$atype}->{$locus}."</td></tr>";
      }
    }
  }
  $rows .= qq{</table>};
  $rows .= "</body></html>";

  open (my $fh, '>', $html_output) or die $!;
  print $fh $rows;

  return;
}

sub count_trans_with_supporting_evi {

  my $gene = shift;
  my $supported_trans_of_set;

  foreach my $t ( @{$gene->get_all_Transcripts} ){
    foreach my $evi (@{$t->transcript_info->get_all_Evidence} ){
      if ( !$evi ){
        #warn "NO EVI";
        return "no evi";
      }
      else {
        #warn "EVI $evi";
        my $evidence_ori = $evi->name;
        my $evidence = $evidence_ori;
        $evidence =~ s/\w*://;
        if ( $evidence_ori =~ /^Em:/ ){
          #warn $evidence;
          $evidence =~ s/\w*://;
          $supported_trans_of_set++ if ! `pfetch -D $evidence | grep "Homo"`;
          last;
        }
        elsif ( $evidence_ori =~ /^(SW:|Tr:)/ ){
          #warn $evidence;
          $supported_trans_of_set++ if ! `pfetch -D $evidence | grep "HUMAN`;
          last;
        }
      }
    }
  }
  return $supported_trans_of_set;
}

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
