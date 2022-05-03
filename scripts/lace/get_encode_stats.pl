#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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


# get_encode_stats
# typical run: get_encode_stats -ds human -time1 06-11-01 -time2 present

# output stats of
# (A) encode regions for Havana annotated clones blasted against
#   (1) ESTs                                (est2genome - EST_best/ _all)
#   (2) cDNAs                               (vertrna    - cDNA_best / _all)
#   (3) Uniprot_raw, Uniprot_SW, Uniprot_TR (uniprot    - Prot_SW / Prot_TR / Prot_all)
# (B) number of transcript evidences used for building Havana annotated genes (EST_evi/cDNA_evi/Prot_evi) in specified time windows

### Example output:
# REGION               TOTAL_gene UPDTD_gene EST_best   EST_all    EST_evi    cDNA_best  cDNA_all   cDNA_evi   Prot_SW    Prot_TR    Prot_all   Prot_evi
# encode-ENm001-02     94         2          8391       29805      41         0          0          27         0          6875       20015      4


use strict;
use Bio::Otter::Lace::Defaults;
use POSIX 'strftime';
use POSIX 'mktime';
use Time::Local;

$| = 1;

my ($dataset, @sets, $cutoff_time_1, $cutoff_time_2);

my $encode_list = "/nfs/team71/analysis/jgrg/work/encode/encode_sets.list";

my $help = sub { exec('perldoc', $0) };

Bio::Otter::Lace::Defaults::do_getopt(
    'ds|dataset=s' => \$dataset,
    'h|help'       => $help,
    'set=s'        => \@sets,
    'time1=s'      => \$cutoff_time_1,
    'time2=s'      => \$cutoff_time_2
    );

print "ENCODE region updated between $cutoff_time_1 and $cutoff_time_2\n";

$cutoff_time_1 = get_timelocal($cutoff_time_1) if $cutoff_time_1;
$cutoff_time_2 = get_timelocal($cutoff_time_2) if $cutoff_time_2;

my $client   = Bio::Otter::Lace::Defaults::make_Client();
my $dset     = $client->get_DataSet_by_name($dataset);
my $otter_db = $dset->get_cached_DBAdaptor;
my $pipe_db  = Bio::Otter::Lace::PipelineDB::get_pipeline_rw_DBAdaptor($otter_db);

my $sliceAd  = $otter_db->get_SliceAdaptor;
my $geneAd   = $otter_db->get_GeneAdaptor;

# get all encoce sets
unless ( @sets ){
  open(my $fh, '<', $encode_list) or die $!;
  while(<$fh>){
    chomp;
    push(@sets, $_);
  };
  close $fh;
}

printf(
    "%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %s\n",
    "REGION", "TOTAL_gene", "UPDTD_gene",
    "EST_best", "EST_all", "EST_evi",
    "cDNA_best", "cDNA_all", "cDNA_evi",
    "Prot_SW", "Prot_TR", "Prot_all", "Prot_evi"
    );


foreach my $set ( @sets ) {
  warn  $set, "\n";

  my $seqSet    = $dset->get_SequenceSet_by_name($set);
  $dset->fetch_all_CloneSequences_for_SequenceSet($seqSet);
  my $chrom;
  $chrom = $seqSet->CloneSequence_list()->[0]->chromosome;

  my $slice   = $sliceAd->fetch_by_chr_name($chrom);

  my $pipe_slice = Bio::Otter::Lace::Slice->new($client, $dataset, $set, 'chromosome', 'Otter', $slice->chr_name, $slice->chr_start, $slice->chr_end);
  my $region_evidences;

  # 1: newpipe 0: oldpipe
  my @analysis = qw(
    Est2genome_human Est2genome_mouse Est2genome_other
    Est2genome_human_raw Est2genome_mouse_raw Est2genome_other_raw
    vertrna vertrna_raw
    );
  foreach my $analysis_name ( @analysis ) {
    my $dafs = $pipe_slice->get_all_DnaAlignFeatures($analysis_name, 1);
    #warn %{$dafs->[0]};

    # only want non-human hits for cDNA
    if ( $analysis_name =~ /vertrna/ ) {
      foreach my $daf ( @$dafs ) {
        my $human = 0;
        eval { $human = $daf->get_HitDescription->description =~ /Homo sapiens/i;};
        shift @$dafs if !$@ && $human == 1;
      }
    }

    my $feats_num = scalar @$dafs;

    if ( $analysis_name =~ /^Est.*_raw/ ) {
      $region_evidences->{$set}->{'EST_raw'} += $feats_num;
    } elsif ( $analysis_name =~ /^Est/ ) {
      $region_evidences->{$set}->{'EST'} += $feats_num;
    } elsif ( $analysis_name eq 'vertrna' ) {
      $region_evidences->{$set}->{'cDNA'} = $feats_num;
    } else {
      $region_evidences->{$set}->{'cDNA_raw'} = $feats_num;
    }

    print ">$set $analysis_name: ", $feats_num, "\n";
  }

  foreach my $ana (qw(Uniprot_raw Uniprot_SW Uniprot_TR)){
    my $pafs = $pipe_slice->get_all_ProteinAlignFeatures($ana, 1);
    $region_evidences->{$set}->{$ana} = scalar @$pafs;
    print ">$set $ana: ",  scalar @$pafs, "\n";
  }

  my $latest_gene_ids = $geneAd->list_current_dbIDs_for_Slice($slice);
  my ($region_updated, $total_gene, $region_cdnaESTprot_evidences) = get_encode_stats($set, $latest_gene_ids);

  foreach my $region ( sort keys %$region_updated ) {
    warn $region;
    my $est     = $region_evidences->{$region}->{'EST'};
    my $est_r   = $region_evidences->{$region}->{'EST_raw'};
    my $cdna    = $region_evidences->{$region}->{'cDNA'};
    my $cdna_r  = $region_evidences->{$region}->{'cDNA_raw'};
    my $prot_sw = $region_evidences->{$region}->{'Uniprot_SW'};
    my $prot_tr = $region_evidences->{$region}->{'Uniprot_TR'};
    my $prot_r  = $region_evidences->{$region}->{'Uniprot_raw'};
   # my $est     = 0;
#    my $est_r   = 0;
#    my $cdna    = 0;
#    my $cdna_r  = 0;
#    my $prot_sw = 0;
#    my $prot_tr = 0;
#    my $prot_r  = 0;
    my $est_e   = $region_cdnaESTprot_evidences->{$region}->{'EST'};
    my $cdna_e  = $region_cdnaESTprot_evidences->{$region}->{'cDNA'};
    my $prot_e  = $region_cdnaESTprot_evidences->{$region}->{'Protein'};

    printf("%-20s %-10d %-10d %-10d %-10d %-10d %-10d %-10d %-10d %-10d %-10d %-10d %d\n",
           $region, $total_gene->{$region}, $region_updated->{$region},
           $est,  $est_r,  $est_e,
           $cdna, $cdna_r, $cdna_e,
           $prot_sw, $prot_tr, $prot_r, $prot_e);
  }
}


#-----------------------------------------------------------
#                   s u b r o u t i n e s
#-----------------------------------------------------------
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

sub get_encode_stats {

  my ($set, $latest_gene_id) = @_;

  my ($total_gene, $region_updated, $region_cdnaESTprot_evidences);

  foreach my $id ( @$latest_gene_id ) {

    my $gene = $geneAd->fetch_by_dbID($id);

    # total refers to all gene types
    $total_gene->{$set}++;

    if ( $cutoff_time_1 and $cutoff_time_2 ){
        next if $gene->gene_info->timestamp < $cutoff_time_1 or
            $gene->gene_info->timestamp > $cutoff_time_2;
    }

    # always filter out gene type = "obsolete"
    next if $gene->type eq "obsolete";
    next if ($gene->type ne "Known"                  and
             $gene->type ne "Novel_CDS"              and
             $gene->type ne "Novel_transcript"       and
             $gene->type ne "Putative"               and
             $gene->type ne "Processed_pseudogene"   and
             $gene->type ne "Unprocessed_pseudogene" and
             $gene->type ne "Artifact"               and
             $gene->type ne "TEC");

    # updated genes refer to only the above gene types
    $region_updated->{$set}++;

    foreach my $trans ( @{$gene->get_all_Transcripts} ){
      foreach my $ev (@{$trans->transcript_info->get_all_Evidence} ){
        my $type = $ev->type;
        if ( $type eq "EST" or $type eq "cDNA" or $type eq "Protein"){
          $region_cdnaESTprot_evidences->{$set}->{$type}++;
        }
      }
    }
  }

  unless ( $region_updated->{$set} ){
    $region_updated->{$set} = 0;
    $region_cdnaESTprot_evidences->{$set}->{EST} = 0;
    $region_cdnaESTprot_evidences->{$set}->{cDNA} = 0;
    $region_cdnaESTprot_evidences->{$set}->{Protein} = 0;
  }

  return $region_updated, $total_gene, $region_cdnaESTprot_evidences;
}

__END__

