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

use OtterTest::TestRegion qw( check_xml extra_gene add_extra_gene_xml region_is %test_region_params );

my %modules;

BEGIN {
    %modules = (
        region        => 'Bio::Otter::ServerAction::Region',
        script_region => 'Bio::Otter::ServerAction::Script::Region',
        xml_region    => 'Bio::Otter::ServerAction::XML::Region',
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

my ($okay, $region_out, $error) = try_write_region($sa_region, $region);
ok(not($okay), 'attempt to write_region dies as expected');
like($error, qr/Writing region failed to init \[No 'locknums' argument/,
     'error message ok');

my $sa_xml_region = $modules{xml_region}->new_with_slice(OtterTest::TestRegion->local_server);
isa_ok($sa_xml_region, $modules{xml_region});

my $xml = $sa_xml_region->get_region;
ok($xml, 'get_region as XML');
note('Got ', length $xml, ' chrs');
check_xml($xml, 'XML is as expected');

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml, 0);
ok(not($okay), 'attempt to write_region from XML dies as expected');
like($error, qr/Writing region failed to init \[slice_lock_id=0 not found/,
     'error message ok');

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

# This is a bit hacky. Would be better, but harder, to parse and interpret the XML.
# It also assumes that pre- and post-diffs each produce just a single chunk which is
# the added gene.
my $pre_diffs = diff(\$xml, \$new_xml, { STYLE => 'Unified', CONTEXT => 0 });
$pre_diffs =~ s/^[-+ ]//mg;
$pre_diffs =~ s/^@@.*$//mg;
my $post_diffs = diff(\$xml, \$xml2, { STYLE => 'Unified', CONTEXT => 0 });
$post_diffs =~ s/^[-+ ]//mg;
$post_diffs =~ s/^@@.*$//mg;
my $gene_diffs = diff(\$pre_diffs, \$post_diffs);
note("XML diffs:\n", $gene_diffs);

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml2);
ok($okay, 'write_region (unchanged again) from XML');
ok($region_out, 'write_region returns some stuff');

my $xml3 = $sa_xml_region->get_region;
ok($xml3, 'get_region as XML yet again');
is($xml3, $xml2, 'XML unchanged');

($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml);
ok($okay, 'write_region (back to scratch) from XML');
ok($region_out, 'write_region returns some stuff');

my $xml4 = $sa_xml_region->get_region;
ok($xml4, 'get_region as XML again');
is($xml4, $xml, 'XML now changed back');

# Back to using a Bio::Vega::Region object
my $region2 = Bio::Vega::Region->new(
    slice   => $region->slice,
    species => $region->species,
    );
$region2->seq_features(   $region->seq_features);
$region2->clone_sequences($region->clone_sequences);
my @genes = ( $region->genes, extra_gene($region->slice) );
$region2->genes(@genes);

($okay, $region_out, $error) = try_write_region($sa_region, $region2);
ok($okay, 'write_region (new gene) from Bio::Vega::Region object');
ok($region_out, 'write_region returns some stuff');

my $region3 = $sa_region->get_region;
ok ($region3, 'get_region as B:V:Region object again');
region_is($region3, $region2, 'region has extra gene');

($okay, $region_out, $error) = try_write_region($sa_region, $region);
ok($okay, 'write_region (back to scratch) from Bio::Vega::Region object');
ok($region_out, 'write_region returns some stuff');

my $region4 = $sa_region->get_region;
region_is($region4, $region, 'region back to starting point');

($okay, $error) = try_unlock_region($sa_region, $lock);
ok($okay, 'unlocked okay');

done_testing;

sub try_write_region {
    my ($server_action_region, $data_in, $lock_token) = @_;
    my ($ok, $data_out, $err);
    try {
        $server_action_region->server->set_params( data => $data_in );
        $server_action_region->server->set_params( locknums => $lock_token )
          if defined $lock_token;
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
