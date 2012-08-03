#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

use FindBin qw($Bin);

use Bio::Otter::Lace::Exonerate;
use Hum::FastaFileIO;

my @modules;

BEGIN {

    @modules = qw(
        Bio::Otter::Lace::OnTheFly
        Bio::Otter::Lace::OnTheFly::Aligner
        Bio::Otter::Lace::OnTheFly::Aligner::Genomic
        Bio::Otter::Lace::OnTheFly::Aligner::Transcript
        Bio::Otter::Lace::OnTheFly::FastaFile
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

my $path = "$Bin/etc/align";
my $target_file = "${path}/test_clone.fa";
my $query_file  = "${path}/test_query.fa";

my $target = new_ok('Bio::Otter::Lace::OnTheFly::TargetSeq' =>
    [ full_seq => Hum::FastaFileIO->new_DNA_IO($target_file)->read_one_sequence ]
    );

my @seqs = ( Hum::FastaFileIO->new_DNA_IO($query_file)->read_all_sequences );

my $aligner = new_ok( 'Bio::Otter::Lace::OnTheFly::Aligner::Genomic' => [{
    type   => 'OTF_EST',
    seqs   => \@seqs,
    target => $target,
    options => {
        '--bestn'          => 1,
        '-M'               => 500,
        '--maxintron'      => 200000,
        '--score'          => 100,
        '--softmasktarget' => 'yes',
        '--softmaskquery'  => 'yes',
        '--showalignment'  => 'false',
    },
    query_type_options => {
        dna => {
            '--model'           => 'e2g',
            '--geneseed'        => 300,
            '--dnahspthreshold' => 120,
        },
        protein => {
            '--model' => 'p2g',
        },
    },
                                                                         }]);

my $result_set = $aligner->run;
isa_ok($result_set, 'Bio::Otter::Lace::OnTheFly::ResultSet');

my @qids = sort $result_set->query_ids;
is(scalar(@qids), 2, 'n(query_ids)');
is_deeply(\@qids, [qw(BC018923.fwd BC018923.rev)], 'query_ids');

my @new_features = sort feature_sort map { $_->ensembl_features } map { $result_set->by_query_id($_) } @qids;
note("n(new_features): ", scalar(@new_features));

# Do it the old way, for comparison

my $target_seq = $target->target_seq;
my $dna_str = $target_seq->sequence_string;
$dna_str =~ s/-/N/g;
my $target_bio_seq = Bio::Seq->new( -id => $target_seq->name, -seq => $dna_str, -alphabet => 'dna');

my $exonerate = Bio::Otter::Lace::Exonerate->new;
$exonerate->initialise($query_file);
$exonerate->bestn(1);
$exonerate->max_intron_length(200000);
$exonerate->score(100);
$exonerate->dnahsp(120);

my $output = $exonerate->run_exonerate($target_bio_seq, $target_bio_seq);
my @output_features = sort feature_sort @$output;

note("n(output_features): ", scalar(@output_features));
is(scalar @new_features, scalar@output_features, 'n(new_features)');
is_deeply(\@new_features, \@output_features, 'new_features');

done_testing;

sub feature_sort {
    return
        $a->hseqname cmp $b->hseqname
        ||
        $a->start    cmp $b->start
        ||
        $a->end      cmp $b->end;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
