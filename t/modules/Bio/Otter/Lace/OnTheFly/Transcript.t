#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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

use Test::More;

use Test::Otter;
use Test::OtterLaceOnTheFly qw( fixed_transcript_tests build_target run_otf_test );

use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Slice;

use Bio::Vega::Exon;
use Bio::Vega::Transcript;

my @modules;

BEGIN {
    @modules = qw(
        Bio::Otter::Lace::OnTheFly::Builder::Transcript
        Bio::Otter::Lace::OnTheFly::Runner::Transcript
        Bio::Otter::Lace::OnTheFly::Transcript
    );

    foreach my $module ( @modules ) {
        use_ok($module);
    }
}

foreach my $module ( @modules ) {
    critic_module_ok($module);
}

main_tests();
done_testing;


sub main_tests {

    foreach my $test ( fixed_transcript_tests() ) {
        run_test($test);
    }

    return;
}

sub run_test {
    my $test = shift;

    $test->{strict_hit_list} = 1;
    my $type = $test->{type} ||= 'Test_EST';

    my $target = build_target($test);
    my ($result_set, @features) = run_otf_transcript_test($test, $target);

    foreach my $q (keys %{$test->{vulgar}}) {
        my $rs_ga  = $result_set->hit_by_query_id($q)->[0];
        my $exp_ga = Bio::Otter::GappedAlignment
            ->from_vulgar($test->{vulgar}->{$q})
            ->consolidate_introns;
        $exp_ga->score($rs_ga->score);
        is($rs_ga->vulgar_string, $exp_ga->vulgar_string, "vulgar for '$q'");
    }

    my $cs    = Bio::EnsEMBL::CoordSystem->new(
        '-name' => 'OTF Test Coords',
        '-rank' => 1,
        );
    my $slice = Bio::EnsEMBL::Slice->new(
        '-seq_region_name' => 'OTF Test Slice',
        '-start'           => 10_000_000,
        '-end'             => 20_000_000,
        '-coord_system'    => $cs,
        );
    my $gff = $result_set->gff($slice);

    if (@features) {
        ok($gff, 'GFF');
    } else {
        is($gff, undef, 'No GFF if no features');
    }

    return;
}

sub run_otf_transcript_test {
    my ($test, $target) = @_;

    my $transcript = build_vega_transcript($test->{ts_spec}, $test->{ts_strand});

    $test->{builder_class} = 'Bio::Otter::Lace::OnTheFly::Builder::Transcript';
    $test->{runner_class}  = 'Bio::Otter::Lace::OnTheFly::Runner::Transcript';
    $test->{runner_args}   = { vega_transcript => $transcript };

    return run_otf_test($test, $target, { vega_transcript => $transcript });
}

sub build_vega_transcript {
    my ($spec_fn, $strand) = @_;

    open my $spec_fh, '<', $spec_fn or die "failed to open ${spec_fn}: $!";

    # FIXME: duplication with TranscriptWindow->ensEMBL_Transcript_from_tk()
    my $ts = Bio::Vega::Transcript->new;
    $ts->strand($strand);

    while (my $line = <$spec_fh>) {
        chomp $line;
        next if $line =~ /^#/;
        my ($name, $q_start, $q_end, $t_start, $t_end) = split "\t", $line;
        my $exon = Bio::Vega::Exon->new;
        $exon->start($t_start);
        $exon->end($t_end);
        $exon->strand($strand);
        $ts->add_Exon($exon);
    }

    return $ts;
}

1;

# EOF
