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

use Test::More;

use Test::Otter qw( db_or_skipall );
use Test::OtterLaceOnTheFly qw( fixed_genomic_tests build_target run_otf_genomic_test );

use OtterTest::Exonerate;

use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Slice;
use Bio::Otter::Utils::FeatureSort qw( feature_sort );

use Hum::ClipboardUtils;

my @modules;

BEGIN {

    if ($ENV{OTTER_OTF_RUN_LIVE_TESTS}) {
        db_or_skipall();
    }

    @modules = qw(
        Bio::Otter::Lace::OnTheFly::Builder::Genomic
        Bio::Otter::Lace::OnTheFly::Genomic
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

    foreach my $test ( fixed_genomic_tests() ) {
        run_fixed_test($test);
    }
    return;
}

sub run_fixed_test {
    my $test = shift;

    $test->{strict_hit_list} = 1;
    run_test($test);
    return;
}

sub run_test {
    my $test = shift;

    my $type = $test->{type} ||= 'Test_EST';

    my $target = build_target($test);
    my ($result_set, @new_features) = run_otf_genomic_test($test, $target);

    # Do it the old way, for comparison

    my $target_seq = $target->target_seq;
    my $dna_str = $target_seq->sequence_string;
    $dna_str =~ s/-/N/g;
    my $target_bio_seq = Bio::Seq->new( -id => $target_seq->name, -seq => $dna_str, -alphabet => 'dna');

    my $exonerate = OtterTest::Exonerate->new;
    if ($test->{query_path}) {
        $exonerate->initialise($test->{query_path});
    } else {
        $exonerate->query_seq($test->{query_seqs});
        $exonerate->initialise($exonerate->write_seq_file);
    }

    $exonerate->bestn(1);
    $exonerate->max_intron_length(200000);
    $exonerate->score(100);
    $exonerate->dnahsp(120);

    $exonerate->query_type('protein') if $type and $type =~ /protein/i;

    my $output = $exonerate->run_exonerate($target_bio_seq, $target_bio_seq);
    my @output_features = feature_sort @$output;

    note("n(output_features): ", scalar(@output_features));
    is(scalar @new_features, scalar@output_features, 'n(new_features)');
    foreach my $n ( 0 .. scalar(@new_features) - 1 ) {
        my $of = $output_features[$n];

        # old-fashioned exonerate output is not shifted according to the start (marked region),
        # so do it here:
        if (my $start = $test->{start}) {
            my $newf = ref($of)->new_fast({ %$of });
            $newf->start($of->start + $start - 1);
            $newf->end(  $of->end   + $start - 1);
            $of = $newf;
        }

        my $name = $of->hseqname;
        subtest "Feature $n ($name)" => sub {
            foreach my $member (
                qw{
                seqname
                start
                end
                strand

                hseqname
                hstart
                hend
                hstrand

                cigar_string

                percent_id
                score
              }
                )
            {
                is($new_features[$n]->$member(), $of->$member(), $member);
            }
            done_testing;
        }
    }

    my $ana_name = $type =~ /^Unknown/ ? $type       :
        $type eq 'cDNA' ? "OTF_mRNA" : "OTF_$type";
    $exonerate->acedb_homol_tag($ana_name . '_homol');
    $exonerate->genomic_start($target->start);
    $exonerate->genomic_end($target->end);
    $exonerate->method_tag($ana_name);
    $exonerate->sequence_fetcher($result_set->query_seqs_by_name);

    my $old_ace = $exonerate->format_ace_output($target_seq->name, $output);
    my $new_ace = $result_set->ace($target->name) || ''; # $old_ace will be empty string rather than undef
    is($new_ace, $old_ace, 'Ace');

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
    my $new_gff = $result_set->gff($slice);
    # there is no old_gff
    if (@output_features) {
        ok($new_gff, 'GFF');
    } else {
        is($new_gff, undef, 'No GFF if no features');
    }

    return;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
