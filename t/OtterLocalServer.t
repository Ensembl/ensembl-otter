#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;
use Try::Tiny;

use Test::Otter qw( ^db_or_skipall ^data_dir_or_skipall ); # may skip test

my %modules;

BEGIN {
    %modules = (
        localserver => 'Bio::Otter::LocalServer',
        region      => 'Bio::Otter::ServerAction::Region',
        xml_region  => 'Bio::Otter::ServerAction::XML::Region',
        );

    use_ok($_) foreach sort values %modules;
}

critic_module_ok($_) foreach sort values %modules;

my %params = (
    dataset => 'human_test',
    name    => '6',
    type    => 'chr6-18',
    cs      => 'chromosome',
    csver   => 'Otter',
    start   => 2864371,
    end     => 3037940,
    );

my $local_server = new_ok($modules{localserver});
ok($local_server->set_params(%params), 'set_params');
is($local_server->param($_), $params{$_}, "param '$_'") foreach keys %params;

my $otter_dba = $local_server->otter_dba;
isa_ok($otter_dba, 'Bio::Vega::DBSQL::DBAdaptor');

my $sa_region = $modules{region}->new_with_slice($local_server);
isa_ok($sa_region, $modules{region});

my $dna = $sa_region->get_assembly_dna;
ok($dna, 'get_assembly_dna');
note('Got ', length $dna, ' bp');

my $region = $sa_region->get_region;
isa_ok($region, 'Bio::Vega::Region');

TODO: {
    local $TODO = "convert region's clone sequences into tiles :-(, possibly by converting to/from XML";
    fail 'todo';
}
# For now, ensure write_region dies appropriately.
#
my ($okay, $region_out, $error) = try_write_region($sa_region, $region);
ok(not($okay), 'attempt to write_region dies as expected');
like($error, qr/numbers of tiles/, 'error message ok');

ok($local_server->set_params(%params), 'set_params');
my $sa_xml_region = $modules{xml_region}->new_with_slice($local_server);
isa_ok($sa_xml_region, $modules{xml_region});

my $xml = $sa_xml_region->get_region;
ok($xml, 'get_region as XML');
note('Got ', length $xml, ' chrs');

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml);
ok(not($okay), 'attempt to write_region from XML dies as expected');
like($error, qr/not locked/, 'error message ok');

my $local_server_2 = new_ok($modules{localserver}, [ otter_dba => $otter_dba ]);

my $otter_dba_2 = $local_server->otter_dba;
isa_ok($otter_dba_2, 'Bio::Vega::DBSQL::DBAdaptor');
is($otter_dba_2, $otter_dba, 'instantiate with otter_dba');

done_testing;

sub try_write_region {
    my ($sa_class, $data_in) = @_;
    my ($ok, $data_out, $err);
    try {
        $local_server->set_params( data => $data_in );
        $data_out = $sa_class->write_region;
    } catch {
        $err = $_;
    };
    return ($ok, $data_out, $err);
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
