#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/otterlace/server/perl"; # find 'fake' SangerWeb modules
$ENV{HTTP_CLIENTREALM} = 'sanger';                          # emulate a local user
$ENV{DOCUMENT_ROOT}    = '/nfs/WWWdev/SANGER_docs/htdocs';  # use standard otter config (eventually)
use Bio::Otter::ServerScriptSupport;

my $vcf_module;

BEGIN {
    $vcf_module = qw( Bio::Vega::CloneFinder );
    use_ok($vcf_module);
}

critic_module_ok($vcf_module);

my @tests = (
    {
        dataset => 'human',
        queries => {
            OTTHUMT00000039641 =>
                "OTTHUMT00000039641\tOtter:transcript_stable_id\tAL139092.12\tchr6-18\n",

            'OTTHUMG00000014126,OTTHUMP00000015944,RP11-420G6.2' => <<"__EO_RESULT__",
OTTHUMG00000014126\tOtter:gene_stable_id\tAL139092.12\tchr6-18
OTTHUMP00000015944\tOtter:translation_stable_id\tAL139092.12\tchr6-18
RP11-420G6.2\tgene_synonym\tAL139092.12\tchr6-18
__EO_RESULT__

            'ENST00000380773,ENSG00000124535' => <<"__EO_RESULT__",
ENST00000380773\tEnsEMBL:ensembl_havana_transcript:transcript_stable_id\tAL139092.12\tchr6-18
ENST00000380773\tCCDS_db:Ens_Hs_transcript:\tAL139092.12\tchr6-18
ENSG00000124535\tEnsEMBL:ensembl_havana_gene:gene_stable_id\tAL139092.12\tchr6-18
__EO_RESULT__
        },
    },
    {
        dataset => 'zebrafish',
        queries => {
            ENSDARG00000086319 => <<"__EO_RESULT__",
ENSDARG00000086319\tEnsEMBL:ensembl:gene_stable_id\tFQ482077.1,CR847984.14\tchr11_20110419
ENSDARG00000086319\tEnsEMBL:ensembl:gene_stable_id\tFQ482077.1\tchr11_20110419
__EO_RESULT__
        },
    },
    );

foreach my $test ( @tests ) {
    note "Tests for dataset: $test->{dataset}";

    my $server = Bio::Otter::ServerScriptSupport->new;
    $server->param(dataset => $test->{dataset});

    while (my ($query, $result) = each %{$test->{queries}} ) {
        subtest "Query: $query" => sub {
            $server->param('qnames'  => $query);
            my $finder = new_ok($vcf_module => [ $server ]);
            $finder->find;
            is($finder->generate_output, $result, 'result');
            done_testing;
        }
    }
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
