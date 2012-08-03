#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

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

my $path = '/Users/mg13/Work/Misc/Vulgar/RP11-420G6.2-002';

my $target = new_ok('Bio::Otter::Lace::OnTheFly::TargetSeq' =>
    [ full_seq => Hum::FastaFileIO->new_DNA_IO("${path}/test_clone.fa")->read_one_sequence ]
    );

my @seqs = ( Hum::FastaFileIO->new_DNA_IO("${path}/test_query.fa")->read_all_sequences );

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

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
