#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

use Test::Otter qw( ^db_or_skipall ); # may skip test

my ($localserver_module, $region_module);
BEGIN {
    $localserver_module = 'Bio::Otter::LocalServer';
    use_ok($localserver_module);

    $region_module = 'Bio::Otter::ServerAction::Region';
    use_ok($region_module);
}

critic_module_ok($localserver_module);
critic_module_ok($region_module);

my %params = (
    dataset => 'human_test',
    name    => '6',
    type    => 'chr6-18',
    cs      => 'chromosome',
    csver   => 'Otter',
    start   => 2864371,
    end     => 3037940,
    );

my $local_server = $localserver_module->new(\%params);
isa_ok($local_server, $localserver_module);

my $otter_dba = $local_server->otter_dba;
isa_ok($otter_dba, 'Bio::Vega::DBSQL::DBAdaptor');

my $sa_region = $region_module->new_with_slice($local_server, \%params);
isa_ok($sa_region, $region_module);

my $dna = $sa_region->get_assembly_dna;
ok($dna, 'get_assembly_dna');
note('Got ', length $dna, ' bp');

my $region = $sa_region->get_region;
isa_ok($region, 'Bio::Vega::Transform::XML');

my $local_server_2 = $localserver_module->new({otter_dba => $otter_dba});
isa_ok($local_server, $localserver_module);
my $otter_dba_2 = $local_server->otter_dba;
isa_ok($otter_dba_2, 'Bio::Vega::DBSQL::DBAdaptor');
is($otter_dba_2, $otter_dba, 'instantiate with otter_dba');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
