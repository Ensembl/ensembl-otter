#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;
use Test::Otter qw( ^db_or_skipall );
use Time::HiRes qw( gettimeofday tv_interval );

use lib "${ENV{ANACODE_TEAM_TOOLS}}/otterlace/server/perl"; # find 'fake' SangerWeb modules
$ENV{HTTP_CLIENTREALM} = 'sanger';                          # emulate a local user
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
ENSG00000124535\tEnsEMBL:ensembl_havana_gene:gene_stable_id\tAL139092.12\tchr6-18
ENST00000380773\tCCDS_db:Ens_Hs_transcript:\tAL139092.12\tchr6-18
ENST00000380773\tEnsEMBL:ensembl_havana_transcript:transcript_stable_id\tAL139092.12\tchr6-18
__EO_RESULT__
                    'ACOT4' =>
"ACOT4\tgene_name\tAC005225.2\tchr14-04\n",
        },
    },
    {
        dataset => 'zebrafish',
        queries => {
            ENSDARG00000086319 => <<"__EO_RESULT__",
ENSDARG00000086319\tEnsEMBL:ensembl:gene_stable_id\tFQ482077.1\tchr11_20110419
ENSDARG00000086319\tEnsEMBL:ensembl:gene_stable_id\tFQ482077.1,CR847984.14\tchr11_20110419
__EO_RESULT__
        },
    },
    {
        dataset => 'mouse',
        queries => {
            SPDYB => # auto-find the WU: variant
"SPDYB\tgene_name\tAC123686.11\tchr5-38
WU:SPDYB\tgene_synonym\tAC123686.11\tchr5-38",
            "*:SPDYB" => [ # prefix-wildcard finds prefixed variants, slowly
"KO:SPDYB\tgene_name\tAC123686.11\tchr5-38
WU:SPDYB\tgene_synonym\tAC123686.11\tchr5-38", 10 ],
        },
    },
    );

sub do_find {
    my (@param) = @_;
    my $t0 = [ gettimeofday() ];

    # $server can be re-used, only for the same dataset
    my $server = Bio::Otter::ServerScriptSupport->new;
    while (my ($k, $v) = splice @param, 0, 2) {
        $server->param($k, $v);
    }

    my $finder = new_ok($vcf_module => [ $server ]);
    $finder->find;

    return ($finder->generate_output, tv_interval($t0));
}

sub tt_testlist {
    my ($test) = @_;
    note "Tests for dataset: $test->{dataset}";

    while (my ($query, $want) = each %{$test->{queries}} ) {
        my $t_allow = 1.25; # sec - a bit lenient
        ($want, $t_allow) = @$want if ref($want);

        subtest "Query: $query" => sub {
            my ($got, $t_took) =
              do_find(qnames  => $query, dataset => $test->{dataset});
            $got = join "\n", sort split /\n/, $got; # test stability sort
            $want =~ s{\n*\Z}{};
            is($got, $want, "query($query) result");
            cmp_ok($t_took, '<=', $t_allow, "query($query) time");
            done_testing;
        }
    }
    return ();
}

sub tt_overflow {
    my ($got, $t_took) = do_find(dataset => 'human', qnames => 'D*'); # ~ 6k hits
    like($got, qr{\A\tToo many search results}, 'human D* hit overflow');
    return ();
}

sub main {
    tt_testlist($_) foreach @tests;
    tt_overflow();

    done_testing;
    return ();
}

main();

# Local Variables:
# mode: perl
# End:

# EOF
