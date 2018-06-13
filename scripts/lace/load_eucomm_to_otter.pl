#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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
use Bio::EnsEMBL::AssemblyMapper;
use Bio::EnsEMBL::Analysis;

# typical params:  perl load_eucomm_to_otter.pl -ds mouse -eucomm your_eucommfile -verbose > ! load_eucomm.log
# the script no longer requires vega_db
# but requires original dataset format like:
# similarity     OTTMUSE00000134685      U1R     U1R     chr2-03 25200208        25200257        +       .       .
# where column 5 has the sequence set info and can be queried from vega_db like
# SELECT es.stable_id, s.name
# FROM exon_stable_id es, exon e, seq_region s
# WHERE es.stable_id = 'OTTMUSE00000000701'
# AND es.exon_id=e.exon_id
# AND e.seq_region_id=s.seq_region_id
# AND s.coord_system_id=1


my ($dataset, $eucommFile, $verbose);
my $help = sub { exec('perldoc', $0) };

Bio::Otter::Lace::Defaults::do_getopt(
    'ds|dataset=s' => \$dataset, # eg, human or mouse or zebrafish
    'h|help'       => $help,
    'eucomm=s'     => \$eucommFile,
    'verbose'      => \$verbose
    ) or $help->(); # plus default options
$help->() unless ( $dataset && $eucommFile );

my $client      = Bio::Otter::Lace::Defaults::make_Client();
my $dset        = $client->get_DataSet_by_name($dataset);
my $otter_db    = $dset->get_cached_DBAdaptor;
my $mapper_ad   = $otter_db->get_AssemblyMapperAdaptor();
my $sf_ad       = $otter_db->get_SimpleFeatureAdaptor();
my $rca         = $otter_db->get_RawContigAdaptor;

{

  my $atype_feats = parse_eucomm_oligos($eucommFile);
  load_simple_features($atype_feats, $otter_db);
  check_duplicates($otter_db);

}

sub parse_eucomm_oligos {

  my $eucommFile = shift;

  my $atype_feats = {};

  open my $data, '<', $eucommFile or die $!;
  while ( <$data> ) {
    my @data = split(/\t/, $_);
    # similarity     OTTMUSE00000134685      U1R     U1R     chr2-03 25200208        25200257        +       .       .
    push(@{$atype_feats->{$data[4]}}, [$data[1], $data[2], $data[5], $data[6]]);
  }

  if ( $verbose ){
    my $count;
    foreach ( sort keys %$atype_feats ){
      $count += scalar @{$atype_feats->{$_}};
      warn sprintf("%-8s: %d\n", $_, scalar @{$atype_feats->{$_}});
    }
    warn "Total features from original eucomm oligo dataset: $count\n\n";
  }
  return $atype_feats;

}

sub load_simple_features {

  my ($atype_feats, $otter_db) = @_;

  # processing parsed dataset

  my @simpleFeatures;

  foreach my $atype ( sort keys %$atype_feats ) {

    print "Working on $atype\n";

    my $fcounter = 0;

    $atype =~ /chr(\d+)-.+/i;
    my $chr_digit = $1;

    foreach my $feat (  @{$atype_feats->{$atype}} ) {

      my $exonSid    = $feat->[0];
      my $feat_lbl   = $exonSid."_$feat->[1]"."_$atype"; # eg, OTTMUSE00000180348_VR_chr2-03
      my $feat_start = $feat->[2];
      my $feat_end   = $feat->[3];
      my $strand     = 1; # default by Eucomm
      my $chr_start  = 1;
      my $chr_end    = $otter_db->get_ChromosomeAdaptor()->fetch_by_chr_name($chr_digit)->length();

      # preparing coord mapper for whole chr of an assembly_type
      my $mapper     = $mapper_ad->fetch_by_type($atype);
      $mapper_ad->register_region($mapper, $atype, $chr_digit, $chr_start, $chr_end);

      print "\t$feat_lbl: start=$feat_start, end=$feat_end\n" if $verbose;

      # transforming chrom. coord to contig coord
      my @raw_coordlist = $mapper->map_coordinates_to_rawcontig( $chr_digit, $feat_start, $feat_end, $strand );

      if (scalar @raw_coordlist > 1 and $verbose) {
        warn "\t$feat_lbl returns ", scalar @raw_coordlist, " features by feature mapper\n";
      }

      for my $coord (@raw_coordlist) {

        # make simplefeature obj
        print "\tmapped to: contig_id=".$coord->id().", start=".$coord->start().", end=".$coord->end().", strand=".$coord->strand().".\n\n" if $verbose;

        my $analysis = Bio::EnsEMBL::Analysis->new;

        $analysis->dbID(9);
        $analysis->logic_name("EUCOMM_AUTO");

        my $sf = Bio::EnsEMBL::SimpleFeature->new;
        $sf->dbID($coord->id);
        $sf->start($coord->start);
        $sf->end($coord->end);
        $sf->strand($coord->strand);
        $sf->analysis($analysis);
        $sf->display_label($feat_lbl);
        $sf->score(1);

        # now attach a rawContig object to simplefeature
        my $contig = $rca->fetch_by_dbID($coord->id);
        $sf->attach_seq($contig);

        $fcounter++;
        push(@simpleFeatures, $sf);
      }
    }
    warn "$atype: $fcounter features returned by feature mapper\n" if $verbose;
  }

  # now store simple features
  my $counter = 0;
  foreach my $sf (@simpleFeatures ) {
    eval {
      $sf_ad->store($sf);
    };
    $counter++ unless $@;
  }
  print "Losding $counter EUCOMM OLIGO simple_features successfully!\n\n" unless $@;

  return;
}

sub check_duplicates {

  my $dbh = shift;
  my $sth = $dbh->prepare(qq{
    SELECT contig_id, contig_start, contig_end, display_label, simple_feature_id
    FROM simple_feature
    where analysis_id = (SELECT analysis_id FROM analysis WHERE logic_name= 'EUCOMM_AUTO')
    }
      );
  $sth->execute;

  my %simple_feature = ();
  my @to_delete;

  while (my $row = $sth->fetchrow_arrayref) {
    my $dupl = $row->[0].$row->[1].$row->[2].$row->[3];
    push(@{$simple_feature{$dupl}},$row->[4]);
  }

  if ( !%simple_feature ) {
    print "Not getting any data! Somethins is wrong\n";
    $sth->finish;
    $dbh->disconnect;
    exit(0)
  }
  foreach ( keys %simple_feature ) {
    if ( scalar @{$simple_feature{$_}} > 1) {
      my @dupl = sort { $a<=>$b } @{$simple_feature{$_}};
      shift @dupl;              # keep the oldest one
      push(@to_delete, @dupl);  # kick the rest for trashing
    }
  }

  warn "Found ", scalar @to_delete, " eucomm oligo simple_feature_id duplicates.\n";
  warn "@to_delete" if $verbose;

  return;
}



__END__
