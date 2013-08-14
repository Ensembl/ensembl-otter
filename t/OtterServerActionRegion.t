#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Sys::Hostname;
use Test::More;
use Text::Diff;
use Try::Tiny;

use Test::Otter qw( ^db_or_skipall ^data_dir_or_skipall ); # may skip test

use OtterTest::TestRegion qw( check_xml add_extra_gene_xml %test_region_params );

my %modules;

BEGIN {
    %modules = (
        region      => 'Bio::Otter::ServerAction::Region',
        xml_region  => 'Bio::Otter::ServerAction::XML::Region',
        );

    use_ok($_) foreach sort values %modules;
}

critic_module_ok($_) foreach sort values %modules;

my $local_server = OtterTest::TestRegion->local_server; # complete with region params
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

my $sa_xml_region = $modules{xml_region}->new_with_slice(OtterTest::TestRegion->local_server);
isa_ok($sa_xml_region, $modules{xml_region});

my $xml = $sa_xml_region->get_region;
ok($xml, 'get_region as XML');
note('Got ', length $xml, ' chrs');
check_xml($xml, 'XML is as expected');

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml);
ok(not($okay), 'attempt to write_region from XML dies as expected');
like($error, qr/not locked/, 'error message ok');

my $lock;
($okay, $lock, $error) = try_lock_region($sa_region);
ok($okay, 'locked okay');

my $lock2;
($okay, $lock2, $error) = try_lock_region($sa_region);
ok(not($okay), 'second lock attempt fails as expected');

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml);
ok($okay, 'write_region (unchanged) from XML');
ok($region_out, 'write_region returns some stuff');

my $new_xml = add_extra_gene_xml($xml);
($okay, $region_out, $error) = try_write_region($sa_xml_region, $new_xml);
ok($okay, 'write_region (new gene) from XML');
ok($region_out, 'write_region returns some stuff');

my $xml2 = $sa_xml_region->get_region;
ok($xml2, 'get_region as XML again');
isnt($xml2, $xml, 'XML has changed');
my $diffs = diff(\$xml, \$xml2);
note("XML diffs:\n", $diffs);

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml);
ok($okay, 'write_region (back to scratch) from XML');
ok($region_out, 'write_region returns some stuff');

$xml2 = $sa_xml_region->get_region;
ok($xml2, 'get_region as XML again');
is($xml2, $xml, 'XML now changed back');

($okay, $error) = try_unlock_region($sa_region, $lock);
ok($okay, 'unlocked okay');

done_testing;

sub try_write_region {
    my ($server_action_region, $data_in) = @_;
    my ($ok, $data_out, $err);
    try {
        $server_action_region->server->set_params( data => $data_in );
        $data_out = $server_action_region->write_region;
        $ok = 1;
    } catch {
        $err = $_;
    };
    return ($ok, $data_out, $err);
}

sub try_lock_region {
    my ($server_action_region) = @_;
    my ($ok, $data_out, $err);
    try {
        $server_action_region->server->set_params( %test_region_params, hostname => hostname );
        $data_out = $server_action_region->lock_region;
        $ok = 1;
    } catch {
        $err = $_;
    };
    return ($ok, $data_out, $err);
}

sub try_unlock_region {
    my ($server_action_region, $lock_obj) = @_;
    my ($ok, $err);
    try {
        $server_action_region->server->set_params( data => $lock_obj );
        $server_action_region->unlock_region;
        $ok = 1;
    } catch {
        $err = $_;
    };
    return ($ok, $err);
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
