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


use strict;
use Getopt::Long 'GetOptions';
use Bio::Otter::Lace::Defaults;
use DBI;
use Bio::EnsEMBL::SimpleFeature;

# typical params: perl get_eucomm_exon_start_end.pl -ds mouse


{

  my $dataset;

  Bio::Otter::Lace::Defaults::do_getopt(
      'ds|dataset=s' => \$dataset,    # eg, human or mouse or zebrafish
      );

  my $client   = Bio::Otter::Lace::Defaults::make_Client();
  my $dset     = $client->get_DataSet_by_name($dataset);
  my $otter_db = $dset->get_cached_DBAdaptor;
  my $sf_ad    = $otter_db->get_SimpleFeatureAdaptor();
  my $sliceAd  = $otter_db->get_SliceAdaptor;


  my $seq_sets = get_EUCOMM_oligo_seq_sets($otter_db);

  print "Fields: (1)SF_ID\t(2)ANNOTATION\t(3)START\t(4)END\n";
  print "-" x 100, "\n";

  foreach my $set ( keys %$seq_sets ) {

    print "$set\n";
    my $seqSet   = $dset->get_SequenceSet_by_name($set);

    $dset->fetch_all_CloneSequences_for_SequenceSet($seqSet);
    my $chrom = $seqSet->CloneSequence_list()->[0]->chromosome;
    my $slice   = $sliceAd->fetch_by_chr_name($chrom);

    my $logic_name = "EUCOMM";
    my $eucomms = $sf_ad->fetch_all_by_Slice($slice, $logic_name);

    foreach my $eu ( @$eucomms ) {

      my $label = $eu->display_label;
      $label =~ s/\s+\(.*//;

      printf("\t%s\t%s\t%s\t%10s\n", $eu->dbID, $label, $eu->start, $eu->end);
    }
  }
}

sub get_EUCOMM_oligo_seq_sets {

  my $otter_db = shift;
  my $qry = $otter_db->prepare(qq{
    SELECT display_label
    FROM simple_feature
    WHERE analysis_id = (
        SELECT analysis_id
        FROM analysis
        WHERE logic_name='EUCOMM_AUTO')
    }
      );


  $qry->execute;
  my $seq_sets = {};

  while ( my $display_label = $qry->fetchrow ){

    $display_label =~ /.+_(chr.+)/;
    $display_label = $1;

    $seq_sets->{$display_label} = 1 unless $seq_sets->{$display_label};
  }
  return $seq_sets;

}
