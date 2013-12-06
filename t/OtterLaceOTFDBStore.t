#!/usr/bin/env perl

use strict;
use warnings;

use Bio::EnsEMBL::Analysis;

use Test::More;
use Test::Requires qw( Bio::EnsEMBL::DBSQL::Driver::SQLite );

use Test::Otter qw( ^data_dir_or_skipall );
use Test::OtterLaceOnTheFly qw( fixed_tests build_target run_otf_test );

use OtterTest::DB;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

my $module;
BEGIN {
    $module = 'Bio::Otter::Lace::OnTheFly::DBStore';
    use_ok($module);
}
critic_module_ok($module);

my $test_db = OtterTest::DB->new_with_dataset_info(undef, 'human');
$test_db->setup_chromosome_slice;

# FIXME: code duplication with EnsEMBL_DnaAlignFeature.t
my $vega_dba = $test_db->vega_dba;
my $slice = $vega_dba->get_SliceAdaptor->fetch_by_region('chromosome', 'test_chr', 1, 4_000_000);

foreach my $test ( fixed_tests() ) {

    $test->{type} ||= 'Test_EST';
    my ($result_set) = run_otf_test($test, build_target($test));
    my $count = $result_set->db_store($slice);
    ok($count, $test->{name});

    note("Stored $count features");
    my $gff = $result_set->gff_from_db($slice);
    ok($gff, 'GFF');
    note("GFF:\n$gff");

    $result_set->clear_db($slice);
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
