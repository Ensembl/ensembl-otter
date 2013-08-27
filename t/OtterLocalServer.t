#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

use Test::Otter qw( ^db_or_skipall ^data_dir_or_skipall ); # may skip test

use OtterTest::TestRegion qw( %test_region_params );
use Bio::Otter::ServerAction::Region; # a specimen ServerAction.

my $module;

BEGIN {
    $module = 'Bio::Otter::LocalServer';
    use_ok($module);
}

critic_module_ok($module);

my $local_server = new_ok($module);
ok($local_server->set_params(%test_region_params), 'set_params');
is($local_server->param($_), $test_region_params{$_}, "param '$_'") foreach keys %test_region_params;

my $otter_dba = $local_server->otter_dba;
isa_ok($otter_dba, 'Bio::Vega::DBSQL::DBAdaptor');

my $sa_region = Bio::Otter::ServerAction::Region->new_with_slice($local_server);
isa_ok($sa_region, 'Bio::Otter::ServerAction::Region');

my $dna = $sa_region->get_assembly_dna;
ok($dna, 'get_assembly_dna');
note('Got ', length $dna, ' bp');

my $region = $sa_region->get_region;
isa_ok($region, 'Bio::Vega::Region');

my $local_server_2 = new_ok($module, [ otter_dba => $otter_dba ]);

my $otter_dba_2 = $local_server->otter_dba;
isa_ok($otter_dba_2, 'Bio::Vega::DBSQL::DBAdaptor');
is($otter_dba_2, $otter_dba, 'instantiate with otter_dba');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
