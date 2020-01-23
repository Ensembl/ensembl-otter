#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Sys::Hostname;
use Test::More tests => 6;
use Text::Diff;
use Try::Tiny;

use File::Temp qw( tempdir );

use Hum::Ace::Assembly;

use Test::Otter qw( ^db_or_skipall ^data_dir_or_skipall OtterClient ); # may skip test

use OtterTest::AceDatabase;
use OtterTest::TestRegion;

my %modules;

BEGIN {
    %modules = (
        region        => 'Bio::Otter::ServerAction::Region',
        script_region => 'Bio::Otter::ServerAction::Script::Region',
        xml_region    => 'Bio::Otter::ServerAction::XML::Region',
        );

    use_ok($_) foreach sort values %modules;
}

sub main {
    subtest critic_tt => \&critic_tt;
    subtest test_regions_tt => \&test_regions_tt;
    subtest DE_line_equiv_tt => \&DE_line_equiv_tt;
#    subtest DE_line_cases_tt => \&DE_line_cases_tt; # no cases yet
    return 0;
}

exit main();


sub critic_tt {
    critic_module_ok($_) foreach sort values %modules;
    return;
}


sub test_regions_tt {
    my $test_region = OtterTest::TestRegion->new(0);
    my $local_server = $test_region->local_server; # complete with region params
    my $sa_region = $modules{region}->new_with_slice($local_server);
    isa_ok($sa_region, $modules{region});

    my $hash = $sa_region->get_assembly_dna;
    my $dna = $hash->{dna};
    is($dna, $test_region->assembly_dna(), 'get_assembly_dna');

    my $region = $sa_region->get_region;
    isa_ok($region, 'Bio::Vega::Region');

    my ($okay, $region_out, $error) = try_write_region($sa_region, $region);
    ok(not($okay), 'attempt to write_region dies as expected');
    like($error, qr/Writing region failed to init \[No 'locknums' argument/,
         'error message ok');

    # Need a new local_server as params get consumed as used.
    $local_server = $test_region->local_server; # complete with region params
    my $sa_xml_region = $modules{xml_region}->new_with_slice($local_server);
    isa_ok($sa_xml_region, $modules{xml_region});

    my $xml = $sa_xml_region->get_region;
    ok($xml, 'get_region as XML');
    note('Got ', length $xml, ' chrs');
    $test_region->xml_matches($xml, 'XML is as expected');
    # if it's not, consider the commented Reset below

    ($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml, 0);
    ok(not($okay), 'attempt to write_region from XML dies as expected');
    like($error, qr/Writing region failed to init \[slice_lock_id=0 not found/,
         'error message ok');

    my $lock;
    ($okay, $lock, $error) = try_lock_region($test_region, $sa_region);
    if (ok($okay, 'locked okay')) {
        note explain $lock;
    } else {
        diag "error: $error";
        diag "Remove old locks with\n  scripts/loutre/show_locks -dataset human_test -interrupt -machine Bio.Otter.Server.Support.Local";
    }

    my $lock2;
    ($okay, $lock2, $error) = try_lock_region($test_region, $sa_region);
    ok(not($okay), 'second lock attempt fails as expected') or diag explain $lock2;


    ###  Reset to match the data.
    #    Useful for when test gets out of sync.
    #
    # To get the authors changed, ensure each gene in the region will need
    # a save.
    if (0) {
        my @rst = try_write_region($sa_xml_region, $test_region->xml_region, $lock->{locknums});
        my @unl = try_unlock_region($sa_region, $lock->{locknums});
        die explain { did_reset => \@rst, unlock => \@unl };
    }

    ($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml, $lock->{locknums});
    ok($okay, 'write_region (unchanged) from XML') or diag "error: $error";
    ok($region_out, 'write_region returns some stuff');

    my $new_xml = $test_region->add_extra_gene_xml($xml);
    ($okay, $region_out, $error) = try_write_region($sa_xml_region, $new_xml, $lock->{locknums});
    ok($okay, 'write_region (new gene) from XML')
      or diag explain { error => $error, new_xml => $new_xml, region_out => $region_out };
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

    ($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml2, $lock->{locknums});
    ok($okay, 'write_region (unchanged again) from XML');
    ok($region_out, 'write_region returns some stuff');

    my $xml3 = $sa_xml_region->get_region;
    ok($xml3, 'get_region as XML yet again');
    is($xml3, $xml2, 'XML unchanged');

    ($okay, $region_out, $error) = try_write_region($sa_xml_region, $xml, $lock->{locknums});
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
    my @genes = ( $region->genes, $test_region->extra_gene($region->slice) );
    $region2->genes(@genes);

    ($okay, $region_out, $error) = try_write_region($sa_region, $region2, $lock->{locknums});
    ok($okay, 'write_region (new gene) from Bio::Vega::Region object');
    ok($region_out, 'write_region returns some stuff');

    my $region3 = $sa_region->get_region;
    ok ($region3, 'get_region as B:V:Region object again');
    $test_region->region_is($region3, $region2, 'region has extra gene');

    ($okay, $region_out, $error) = try_write_region($sa_region, $region, $lock->{locknums});
    ok($okay, 'write_region (back to scratch) from Bio::Vega::Region object');
    ok($region_out, 'write_region returns some stuff');

    my $region4 = $sa_region->get_region;
    $test_region->region_is($region4, $region, 'region back to starting point');

    ($okay, $error) = try_unlock_region($sa_region, $lock->{locknums});
    ok($okay, 'unlocked okay');

    return;
}

sub try_write_region {
    my ($server_action_region, $data_in, $lock_token) = @_;
    my ($ok, $data_out, $err);
    try {
        $server_action_region->server->set_params( data => $data_in );
        $server_action_region->server->add_param( locknums => $lock_token )
          if defined $lock_token;
        $data_out = $server_action_region->write_region;
        $ok = 1;
    } catch {
        $err = $_;
    };
    return ($ok, $data_out, $err);
}

sub try_lock_region {
    my ($test_region, $server_action_region) = @_;
    my ($ok, $data_out, $err);
    try {
        $server_action_region->server->set_params( %{$test_region->region_params}, hostname => hostname );
        $data_out = $server_action_region->lock_region;
        $ok = 1;
    } catch {
        $err = $_;
    };
    return ($ok, $data_out, $err);
}

sub try_unlock_region {
    my ($server_action_region, $lock_token) = @_;
    my ($ok, $err);
    try {
        $server_action_region->server->set_params(locknums => $lock_token);
        $server_action_region->unlock_region;
        $ok = 1;
    } catch {
        $err = $_;
    };
    return ($ok, $err);
}


# Check the new server-side implementation (B:O:ServerAction::Region)
# matches the old (Hum::*) one.
#
# Requires making an Ace database for each region.
sub DE_line_equiv_tt {
    my $tmpdir = tempdir('DE_line_equiv.XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my @r = (
        OtterTest::TestRegion->new('human_test:chr12-38:30351955-34820185'),
      );

    for (my $i=0; $i<@r; $i++) {
        my $test_region = $r[$i];
        diag "Next: $i : ", $test_region->base_name;
        _DE_region_equiv("$tmpdir/ace_$i", $i, $test_region);
    }

    return;
}

sub _DE_region_equiv {
    my ($acehome, $label, $test_region) = @_;
    ### Get DE-line the old way

    my $rp = $test_region->region_params;
    my $adb = OtterTest::AceDatabase->new_from_slice_params(
        $acehome,
        "DE_line_cmp:$label",
        @{$rp}{qw( dataset chr cs csver name start end )},
        );
    my $assembly = $adb->fetch_assembly;

    # Do we need to load up all the SubSeqs from a GFF?
    # Is it worth having a SessionWindow here to do that?

    my $slice = $adb->slice;

    foreach my $clone ($assembly->get_all_Clones) {
        my $ace_desc = $assembly->generate_description_for_clone($clone);
        # may be false?  "I didn't find anything to describe"  (619b6039)

        my $clone_slice = $slice->clone_near
          ($slice->start + $clone->assembly_start,
           $slice->start + $clone->assembly_end);
        # untested, is this the right patch?

        # Make the server_action region for this slice
        my $local_server = Bio::Otter::Server::Support::Local->new;
        $local_server->authorized_user('anacode');
        $local_server->set_params(Bio::Otter::Lace::Client->slice_query($clone_slice));
        my $sa_region = $modules{region}->new_with_slice($local_server);

        my $remote_desc = $sa_region->DE_region()->{'description'};
        my $orig_desc = $remote_desc;

        my $strip_punct = qr/[,;]/;
        $ace_desc    =~ s/$strip_punct//g;
        $remote_desc =~ s/$strip_punct//g;

        $ace_desc =~ s/\s+[A-Z]+\d+-\d+[A-Z]+\d+\.\d+//g; # ' RP11-551L14.1' => ''

        $remote_desc =~ s/the [35]' end/part/g;
        $remote_desc =~ s/an internal part/part/g;

        is($remote_desc, $ace_desc,
           "desc for ".$clone->clone_name." vs. ".$clone_slice->name);
        note $orig_desc;
    }

    return;
}

# Check the new server-side implementation (B:O:ServerAction::Region)
# produces expected output for some fixed input.
sub DE_line_cases_tt {
    fail('no test cases yet');
}


1;
