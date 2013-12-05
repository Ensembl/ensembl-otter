# Common test code for Bio::Otter::Lace::OnTheFly* tests.

package Test::OtterLaceOnTheFly;

use strict;
use warnings;

use Exporter qw(import);
use FindBin qw($Bin);
use Test::More;

use Bio::Otter::Lace::OnTheFly::Aligner::Genomic;
use Bio::Otter::Lace::OnTheFly::TargetSeq;
use Bio::Otter::Utils::FeatureSort qw( feature_sort );
use Hum::FastaFileIO;

our @EXPORT_OK = qw( fixed_tests build_target run_otf_test );

my $path = "$Bin/etc/align";

my @tests = (
    {
        name        => 'test_clone vs. test_query',
        target_path => "${path}/test_clone.fa",
        query_path  => "${path}/test_query.fa",
        query_ids   => [qw(BC018923.fwd BC018923.rev)],
    },
    {
        name        => 'test_clone vs. test_query with mark',
        target_path => "${path}/test_clone.fa",
        query_path  => "${path}/test_query.fa",
        query_ids   => [qw(BC018923.fwd BC018923.rev)],
        start       => 35000,
        end         => 141000,
    },
    {
        name        => 'AL139092 vs. BC018923',
        target_path => "${path}/AL139092.12.fasta",
        query_path  => "${path}/BC018923.fasta",
        query_ids   => [qw(ENA|BC018923|BC018923.2)],
    },
    {
        name        => 'AL139092 vs. BI831275',
        target_path => "${path}/AL139092.12.fasta",
        query_path  => "${path}/BI831275.fasta",
        query_ids   => [qw(ENA|BI831275|BI831275.1)],
    },
    {
        name        => 'AL133351 vs. BG212959.1',
        target_path => "${path}/AL133351.34.fasta",
        query_path  => "${path}/BG212959.1.fa",
        query_ids   => [qw(BG212959.1)],
    },
    {
        name        => 'AL139092 vs. protein Q96S55',
        target_path => "${path}/AL139092.12.fasta",
        query_path  => "${path}/Q96S55.fasta",
        query_ids   => [qw(sp|Q96S55|WRIP1_HUMAN)],
        type        => 'Test_Protein',
    },
    {
        name        => 'test_clone vs. protein Q96S55',
        target_path => "${path}/test_clone.fa",
        query_path  => "${path}/Q96S55.fasta",
        query_ids   => [qw(sp|Q96S55|WRIP1_HUMAN)],
        type        => 'Test_Protein',
    },
    {
        name        => 'AL133351 vs. protein Q8VHQ0.1',
        target_path => "${path}/AL133351.34.fasta",
        query_path  => "${path}/Q8VHQ0.fasta",
        query_ids   => [qw(Q8VHQ0.1)],
        type        => 'Test_Protein',
    },
    {
        name        => 'CR753817.13 vs. AW134265.1 (trim leading/trailing indels)',
        target_path => "${path}/CR753817.13.fasta",
        query_path  => "${path}/AW134265.1.fasta",
        query_ids   => [qw(AW134265.1)],
    },
    );

sub fixed_tests {
    return @tests;
}

sub build_target {
    my $test = shift;

    $test->{target_seq} ||= Hum::FastaFileIO->new_DNA_IO($test->{target_path})->read_one_sequence;

    my @target_seq_args = ( full_seq => $test->{target_seq} );
    push @target_seq_args, start => $test->{start} if $test->{start};
    push @target_seq_args, end   => $test->{end}   if $test->{end};

    my $target = new_ok('Bio::Otter::Lace::OnTheFly::TargetSeq' => \@target_seq_args);
    return $target;
}

sub run_otf_test {
    my ($test, $target) = @_;

    note 'Test: ', $test->{name};

    if ($test->{query_path}) {
        $test->{query_seqs} = [ Hum::FastaFileIO->new_DNA_IO($test->{query_path})->read_all_sequences ];
    }

    my $aligner = new_ok( 'Bio::Otter::Lace::OnTheFly::Aligner::Genomic' => [{
        type       => $test->{type},
        query_seqs => $test->{query_seqs},
        target     => $target,
                                                                             }]);

    my $result_set = $aligner->run;
    isa_ok($result_set, 'Bio::Otter::Lace::OnTheFly::ResultSet');

    my @qids = sort $result_set->hit_query_ids;
    if ($test->{strict_hit_list}) {
        is(scalar(@qids), scalar(@{$test->{query_ids}}), 'n(query_ids)');
        is_deeply(\@qids, $test->{query_ids}, 'query_ids');
    }

    my @gapped_alignments =  map { @{$result_set->hit_by_query_id($_)} } @qids;
    my @new_features;
    foreach my $ga ( @gapped_alignments ) {
        push @new_features, $ga->ensembl_features;
        note $ga->query_id, ': QS ', $ga->query_strand, ', TS ', $ga->target_strand, ', GO ', $ga->gene_orientation;
    }
    @new_features = feature_sort @new_features;
    note("n(new_features): ", scalar(@new_features));

    return $result_set, @new_features;
}

1;
