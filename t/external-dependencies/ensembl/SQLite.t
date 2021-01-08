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


use strict;
use warnings;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DnaDnaAlignFeature;

use Test::Otter qw( ^data_dir_or_skipall );
use OtterTest::DB;

use Test::More;
use Test::Requires qw( Bio::EnsEMBL::DBSQL::Driver::SQLite );

my $test_db = OtterTest::DB->new_with_dataset_info(dataset_name => 'human');
$test_db->setup_chromosome_slice;

my $vega_dba = $test_db->vega_dba;
isa_ok($vega_dba, 'Bio::Vega::DBSQL::DBAdaptor');
my $daf_adaptor = $vega_dba->get_DnaAlignFeatureAdaptor;
isa_ok($daf_adaptor, 'Bio::EnsEMBL::DBSQL::DnaAlignFeatureAdaptor');

my $slice = $vega_dba->get_SliceAdaptor->fetch_by_region('chromosome', 'test_chr', 1, 4_000_000);
isa_ok($slice, 'Bio::EnsEMBL::Slice');

my $analysis = Bio::EnsEMBL::Analysis->new( -LOGIC_NAME => 'otter_test_analysis' );

# Cut'n'paste from EnsEMBL dnaAlignFeatureAdaptor.t
my $start      = 100_100;
my $end        = 100_200;
my $strand     = 1;
my $hstart     = 10;
my $hend       = 110;
my $hstrand    = -1;
my $hseqname   = 'test';
my $score      = 80;
my $percent_id = 90;
my $evalue     = 23.2;
my $cigar_string = '100M';
my $hcoverage  = 99.5;
my $external_db_id = 2200;

my $feat = Bio::EnsEMBL::DnaDnaAlignFeature->new
  (-START  => $start,
   -END    => $end,
   -STRAND => $strand,
   -SLICE  => $slice,
   -HSTART => $hstart,
   -HEND   => $hend,
   -HSTRAND => $hstrand,
   -HSEQNAME => $hseqname,
   -CIGAR_STRING => '100M',
   -PERCENT_ID => $percent_id,
   -SCORE    => $score,
   -P_VALUE => $evalue,
   -ANALYSIS => $analysis,
   -HCOVERAGE => $hcoverage,
   -EXTERNAL_DB_ID => $external_db_id );

ok(not($feat->is_stored($vega_dba)), 'not stored yet');

$daf_adaptor->store($feat);

ok($feat->is_stored($vega_dba), 'now stored');

my $dbID = $feat->dbID();
my $r_feat = $daf_adaptor->fetch_by_dbID($dbID, 'contig');

is($r_feat->dbID, $dbID, "dbID");
is($r_feat->start, $start, "start");
is($r_feat->end, $end, "end");
is($r_feat->strand, $strand, "strand");
is($r_feat->slice->name, $slice->name, "slice->name");
is($r_feat->hstart, $hstart, "hstart");
is($r_feat->hend, $hend, "hend");
is($r_feat->hstrand, $hstrand, "hstrand");
is($r_feat->hseqname, $hseqname, "hseqname");
is($r_feat->cigar_string, $cigar_string, "cigar_string");
is($r_feat->percent_id, $percent_id, "percent_id");
is($r_feat->score, $score, "score");
is($r_feat->p_value, $evalue, "p_value");
is($r_feat->analysis->logic_name, $analysis->logic_name, "analysis->logic_name");
is($r_feat->external_db_id, $external_db_id, "external_db_id");
is($r_feat->hcoverage, $hcoverage, "hcoverage");

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
