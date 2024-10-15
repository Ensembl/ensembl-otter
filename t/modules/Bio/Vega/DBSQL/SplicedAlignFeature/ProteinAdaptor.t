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


use strict;
use warnings;

use Bio::EnsEMBL::Analysis;
use Bio::Vega::SplicedAlignFeature::Protein;

use Test::Otter qw( ^data_dir_or_skipall );
use OtterTest::DB;

use Test::More;
use Test::Requires qw( Bio::EnsEMBL::DBSQL::Driver::SQLite );

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $saf_pa_module;
BEGIN {
    $saf_pa_module = 'Bio::Vega::DBSQL::SplicedAlignFeature::ProteinAdaptor';
    use_ok($saf_pa_module);
}
critic_module_ok($saf_pa_module);

my $test_db = OtterTest::DB->new_with_dataset_info(dataset_name => 'human');
$test_db->setup_chromosome_slice;

my $vega_dba = $test_db->vega_dba;
isa_ok($vega_dba, 'Bio::Vega::DBSQL::DBAdaptor');
my $psaf_adaptor = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;
isa_ok($psaf_adaptor, 'Bio::Vega::DBSQL::SplicedAlignFeature::ProteinAdaptor');

# Cut'n'paste from EnsEMBL_DnaAlignFeature.t
my $slice = $vega_dba->get_SliceAdaptor->fetch_by_region('chromosome', 'test_chr', 1, 4_000_000);
isa_ok($slice, 'Bio::EnsEMBL::Slice');
my $analysis = Bio::EnsEMBL::Analysis->new( -LOGIC_NAME => 'otter_test_analysis' );

# Mostly cut'n'paste from EnsEMBL proteinAlignFeatureAdaptor.t
my $start      = 100_100;
my $end        = 100_198;
my $strand     = 1;
my $hstart     = 10;
my $hend       = 42;
my $hstrand    = 1;
my $hseqname   = 'test';
my $score      = 80;
my $percent_id = 90;
my $evalue     = 23.2;
my $cigar_string = '99M';
my $hcoverage  = 99.5;
my $external_db_id = 2200;

my $feat = Bio::Vega::SplicedAlignFeature::Protein->new
  (-start  => $start,
   -end    => $end,
   -strand => $strand,
   -slice  => $slice,
   -hstart => $hstart,
   -hend   => $hend,
   -hstrand => $hstrand,
   -hseqname => $hseqname,
   -cigar_string => $cigar_string,
   -percent_id => $percent_id,
   -score    => $score,
   -p_value => $evalue,
   -analysis => $analysis,
   -hcoverage => $hcoverage,
   -external_db_id => $external_db_id);

ok(not($feat->is_stored($vega_dba)), 'not stored yet');

$psaf_adaptor->store($feat);

ok($feat->is_stored($vega_dba), 'now stored');

my $dbID = $feat->dbID();
my $r_feat = $psaf_adaptor->fetch_by_dbID($dbID);
isa_ok($r_feat, 'Bio::Vega::SplicedAlignFeature::Protein');

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
