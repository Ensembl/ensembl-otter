#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

use Test::Otter qw( db_or_skipall );
use Test::OtterLaceOnTheFly qw( fixed_tests build_target run_otf_test );

use OtterTest::AccessionTypeCache;
use OtterTest::Exonerate;

use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Slice;
use Bio::Otter::Server::Support::Local;
use Bio::Otter::ServerAction::Region;
use Bio::Otter::Utils::FeatureSort qw( feature_sort );

use Hum::ClipboardUtils;

my @modules;

BEGIN {

    if ($ENV{OTTER_OTF_RUN_LIVE_TESTS}) {
        db_or_skipall();
    }

    @modules = qw(
        Bio::Otter::Lace::OnTheFly
        Bio::Otter::Lace::OnTheFly::Aligner
        Bio::Otter::Lace::OnTheFly::Aligner::Genomic
        Bio::Otter::Lace::OnTheFly::Aligner::Transcript
        Bio::Otter::Lace::OnTheFly::FastaFile
        Bio::Otter::Lace::OnTheFly::Format::Ace
        Bio::Otter::Lace::OnTheFly::Format::GFF
        Bio::Otter::Lace::OnTheFly::Genomic
        Bio::Otter::Lace::OnTheFly::QueryValidator
        Bio::Otter::Lace::OnTheFly::ResultSet
        Bio::Otter::Lace::OnTheFly::TargetSeq
        Bio::Otter::Lace::OnTheFly::Transcript
    );

    foreach my $module ( @modules ) {
        use_ok($module);
    }
}

foreach my $module ( @modules ) {
    critic_module_ok($module);
}

my @todo_tests = (
    );

my %species_tests = (
    human => [
        { title => 'AL133351.34', type => 'chr6-18', start => 2864371, end => 3037940, },
    ],
    mouse => [
        { title => 'AC144852+5k', type => 'chr10-38', start => 127162862, end => 127313035, },
    ],
    zebrafish => [
        { title => 'CR753817.13', type => 'chr6_20110419', start => 35489955, end => 35724691, },
    ],
    tas_devil => [
        { title => 'With_gap', type => 'MHC-06', start => 139316, end => 424882, },
    ],
    );

main_tests();
done_testing;

sub main_tests {

    foreach my $test ( fixed_tests() ) {
        run_fixed_test($test);
    }

  TODO: {
      local $TODO = "Protein handling not yet compatible for frameshift and split codon";

      foreach my $test ( @todo_tests ) {
          run_fixed_test($test);
      }
    }

  SKIP: {

      unless ($ENV{OTTER_OTF_RUN_LIVE_TESTS}) {
          my $msg = 'live tests as OTTER_OTF_RUN_LIVE_TESTS is not set';
          diag "skipping $msg"; # to show in non-verbose mode.
          skip $msg, 1;
      }

      my $at_cache = OtterTest::AccessionTypeCache->new();

      while (my ($species, $regions) = each %species_tests) {
          note("Live tests for: $species");
          my $local_server = Bio::Otter::Server::Support::Local->new();
          foreach my $region ( @$regions ) {
              $local_server->set_params(%$region, dataset => $species, cs => 'chromosome', csver => 'Otter');
              my $sa_region = Bio::Otter::ServerAction::Region->new_with_slice($local_server);
              run_region($region->{title}, $sa_region, $at_cache);
          }
      }

    } # SKIP

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
    my ($result_set, @new_features) = run_otf_test($test, $target);

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
    ok($new_gff, 'GFF');

    return;
}

sub run_region {
    my ($title, $sa_region, $at_cache) = @_;
    note("  Region: ", $title);

    # FIXME: get_assembly_dna should return components
    my ($dna, @tiles) = split(/\n/, $sa_region->get_assembly_dna);
    my $target_seq = Hum::Sequence::DNA->new;
    $target_seq->name($title);
    $target_seq->sequence_string($dna);

    my @genes = $sa_region->get_region->genes;
    foreach my $gene (@genes) {
        note("    Gene: ", $gene->stable_id);
        my $transcripts = $gene->get_all_Transcripts;
        foreach my $ts (@$transcripts) {
            note("      Transcript: ", $ts->stable_id);
            my $evi_list = $ts->evidence_list;
            my $q_validator = get_query_validator($at_cache, $evi_list);
            foreach my $type ( $q_validator->seq_types ) {
                my $seqs = $q_validator->seqs_for_type($type);
                my @seq_names = map{ $_->name } @$seqs;
                note("        ", $type, ": ", join(',', @seq_names));
                run_test({
                    name       => join('_', $ts->stable_id, $type),
                    target_seq => $target_seq,
                    query_seqs => $seqs,
                    query_ids  => \@seq_names,
                    type       => $type,
                         });
            }
        }
    }
    return;
}

sub get_query_validator {
    my ($at_cache, $evi_list) = @_;
    my @evi_names = map { Hum::ClipboardUtils::accessions_from_text($_->name) } @$evi_list;
    my $q_validator = Bio::Otter::Lace::OnTheFly::QueryValidator->new(
        accession_type_cache => $at_cache,
        accessions           => \@evi_names,
        problem_report_cb    => sub {
            my ($self, $msgs) = @_;
            map { diag("QV ", $_, ": ", $msgs->{$_}) if $msgs->{$_} } keys %$msgs;
        },
        long_query_cb        => sub { diag("QV long q: ", shift, "(", shift, ")"); },
        );
    return $q_validator;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
