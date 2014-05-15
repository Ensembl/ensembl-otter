#!/usr/bin/env perl

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

use Hum::Ace::SubSeq;

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

    my $type = $test->{type} ||= 'Test_EST';

    my $target = build_target($test);
    my ($result_set, @features) = run_otf_transcript_test($test, $target);

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

    $test->{builder_class} = 'Bio::Otter::Lace::OnTheFly::Builder::Transcript';
    $test->{runner_class}  = 'Bio::Otter::Lace::OnTheFly::Runner::Transcript';
    $test->{runner_args}   = { transcript => build_transcript($test->{ts_spec}) };

    return run_otf_test($test, $target);
}

sub build_transcript {
    my ($spec_fn) = @_;

    open my $spec_fh, '<', $spec_fn or die "failed to open ${spec_fn}: $!";

    my $ts = Hum::Ace::SubSeq->new;
    $ts->strand(1);             # FIXME!!

    while (my $line = <$spec_fh>) {
        chomp $line;
        next if $line =~ /^#/;
        my ($name, $q_start, $q_end, $t_start, $t_end) = split "\t", $line;
        my $exon = $ts->new_Exon;
        $exon->start($t_start);
        $exon->end($t_end);
    }

    return $ts;
}

1;

# EOF
