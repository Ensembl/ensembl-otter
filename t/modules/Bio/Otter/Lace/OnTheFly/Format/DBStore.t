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


use strict;
use warnings;

use Bio::Otter::Lace::OnTheFly;
use Bio::Otter::Utils::SliceFeaturesGFF;

use Test::More;
use Test::MockObject;
use Test::Requires qw( Bio::EnsEMBL::DBSQL::Driver::SQLite );

use Test::Otter qw( ^data_dir_or_skipall );
use Test::OtterLaceOnTheFly qw( fixed_genomic_tests build_target run_otf_genomic_test );

use OtterTest::DB;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

my $module;
BEGIN {
    $module = 'Bio::Otter::Lace::OnTheFly::Format::DBStore';
    use_ok($module);
}
critic_module_ok($module);

my $test_db = OtterTest::DB->new_with_dataset_info(dataset_name => 'human');
$test_db->setup_chromosome_slice;

# FIXME: code duplication with EnsEMBL_DnaAlignFeature.t
my $vega_dba = $test_db->vega_dba;
my $sfg = Bio::Otter::Utils::SliceFeaturesGFF->new(
    dba   => $vega_dba,
    cs    => 'chromosome',
    name  => 'test_chr',
    start => 1,
    end   => 4_000_000,

    gff_version    => 2,
    extra_gff_args => { use_cigar_exonerate => 1 }, # TEMP for testing
    );

# Mock an OTF object to get at pre_launch_setup()
my $otf = Test::MockObject->new;
$otf->set_true('clear_existing');
$otf->mock('pre_launch_setup', sub { return shift->Bio::Otter::Lace::OnTheFly::pre_launch_setup(@_); });
$otf->mock('logic_names',      sub { return [qw( OTF_Test_EST OTF_Test_Protein )]; });

foreach my $test ( fixed_genomic_tests() ) {

    $test->{type} ||= 'Test_EST';
    my ($result_set) = run_otf_genomic_test($test, build_target($test));
    my $count = $result_set->db_store($sfg->slice);
    ok($count, $test->{name});
    note("Stored $count features");

    $sfg->logic_name($result_set->analysis_name);
    $sfg->feature_kind($result_set->is_protein ? 'ProteinSplicedAlignFeature' : 'DnaSplicedAlignFeature');
    $sfg->gff_source($result_set->analysis_name);
    my $features = $sfg->features_from_slice;
    my $db_gff = $sfg->gff_for_features($features);
    ok($db_gff, 'GFF from DB');

    my $rs_gff = $result_set->gff($sfg->slice);
    $rs_gff =~ s/(percentID \d+\.\d)0(;|$)/$1$2/gm; # strip trailing 0's on percentID
    $rs_gff =~ s/(percentID \d+)\.0+(;|$)/$1$2/gm;    # strip trailing 00's on percentID
    ok($rs_gff, 'GFF from result_set');

    is($db_gff, $rs_gff, 'GFF identical');

    $otf->pre_launch_setup(slice => $sfg->slice); # clears out features from this run
    $sfg->dba->clear_caches;
}

# print "SQLITE: ", $test_db->file, "\n";
# print "Press enter:\n";
# my $enter = <>;

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
