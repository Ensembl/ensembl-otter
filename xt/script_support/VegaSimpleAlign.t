#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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

use Bio::Vega::Utils::Align;
use Bio::Vega::Utils::Evidence qw/reverse_seq/;

use Test::More tests => 80;

my $module = 'Bio::Vega::SimpleAlign';

use_ok($module);
critic_module_ok($module);

# Basics

my $vsa = Bio::Vega::SimpleAlign->new;

isa_ok($vsa, 'Bio::Vega::SimpleAlign');
isa_ok($vsa, 'Bio::SimpleAlign');

can_ok($vsa, 'direction');
can_ok($vsa, 'rank');
can_ok($vsa, 'ensembl_cigar_match');
can_ok($vsa, 'underlap_length');
can_ok($vsa, 'reference_seq');
can_ok($vsa, 'feature_seq');
can_ok($vsa, 'trailing_length');
can_ok($vsa, 'trailing_feature_seq');
can_ok($vsa, 'oversize_inserts');
can_ok($vsa, 'split_exons');

is( $vsa->direction, undef, 'direction not set yet' );
is( $vsa->direction(1), 1,  'set direction forward' );
is( $vsa->direction, 1,     'direction still forward' );
is( $vsa->direction(-1), -1,'set direction reverse' );
is( $vsa->direction, -1,    'direction still reverse' );

is( $vsa->rank, undef,    'rank not set yet' );
is( $vsa->rank(123), 123, 'set rank' );
is( $vsa->rank, 123,      'rank still set' );

# Constructor args

$vsa = Bio::Vega::SimpleAlign->new( -direction => -1, rank => 56 );

isa_ok($vsa, 'Bio::Vega::SimpleAlign');
is( $vsa->direction, -1, 'direction from constructor' );
is( $vsa->rank,      56, 'rank from constructor' );

# promote_BioSimpleAlign

my $sa = Bio::SimpleAlign->new;
$sa->description('BVSA test');

$vsa = Bio::Vega::SimpleAlign->promote_BioSimpleAlign($sa);

isa_ok($vsa, 'Bio::Vega::SimpleAlign');
isa_ok($vsa, 'Bio::SimpleAlign');
is( $vsa->description, 'BVSA test', 'description carried forward' );

# ensembl_cigar_match

my $seq = sequences();

$vsa = do_align(
    Bio::Seq->new(-seq => $seq->{OTTHUMT00000077359}, -id => 'refseq',
                  -start => 1, -end => length($seq->{OTTHUMT00000077359})),
    Bio::Seq->new(-seq => $seq->{'BI760949.1'}, -id => 'BI760949.1',
                  -start => 1, -end => length($seq->{'BI760949.1'})),
    0,                          # don't reverse feature
    );

isa_ok($vsa, 'Bio::Vega::SimpleAlign');

isa_ok($vsa->reference_seq, 'Bio::LocatableSeq');
isa_ok($vsa->feature_seq, 'Bio::LocatableSeq');

my $ref_out = $vsa->reference_seq->seq;
my $f_out   = $vsa->feature_seq->seq;

$ref_out =~ tr/-//d;
$f_out   =~ tr/-//d;

is( $ref_out, $seq->{OTTHUMT00000077359}, 'ref seq preserved');
is( $f_out,   $seq->{'BI760949.1'},   'feature seq preserved');

is( $vsa->ensembl_cigar_match, '0M214I697MD50M2D12MD7M2D10M104D', 'ensembl_cigar_match' );

is( $vsa->underlap_length, 0, 'no underlap' );

my $vsa2 = do_align(
    Bio::Seq->new(-seq => $seq->{OTTHUMT00000077344}, -id => 'refseq',
                  -start => 1, -end => length($seq->{OTTHUMT00000077344})),
    Bio::Seq->new(-seq => $seq->{'BF376291.1'}, -id => 'BF376291.1',
                  -start => 1, -end => length($seq->{'BF376291.1'})),
    0,                          # don't reverse feature
    );

isa_ok($vsa2, 'Bio::Vega::SimpleAlign');

is( $vsa2->ensembl_cigar_match, '0M23D4M6I9M19D3M10D3MD7MI5MD284MI3M11I6M68I', 'ensembl_cigar_match - vsa 2' );

is( $vsa2->underlap_length, 23, 'underlap exists');

is( $vsa->trailing_length, 104, 'trailing exists' );
is( $vsa->trailing_feature_seq,
    'GCTTGGAATTCTAATTCTGTCTTGGATACCTTGGTATTTTATGCCAAAAACTCCTATCTCCTTTCCTTTTATGACACGAGAAGTAGGTTGAGGGTTGGGATCCC',
    'trailing_feature_seq');
is( $vsa2->trailing_length, 0, 'no trailing on vsa2');
ok( not($vsa2->trailing_feature_seq), 'no trailing feature seq on vsa2');

ok( not($vsa->oversize_inserts), 'no oversize_inserts at default tolerance');
is( scalar($vsa->oversize_inserts(2)), 2, 'oversize_inserts at tol 2');
is( scalar($vsa->oversize_inserts(1)), 4, 'oversize_inserts at tol 1');

# exonify

my $vsa3 = Bio::Vega::SimpleAlign->new;
$vsa3->add_seq( Bio::LocatableSeq->new(
                    -seq => '---ABCDE--FGH--JK----',
                    -id => 'refseq',
                    -start => 1,
                    -end   => 10,
                )
    );
$vsa3->add_seq( Bio::LocatableSeq->new(
                    -seq => 'ZYXAB-DEWVF-HUTJKSRQP',
                    -id => 'fseq',
                    -start => 1,
                    -end   => 19,
                )
    );

my %exotests = (
    '01-basic' => {
        exons => [[1,6],[7,10]],
        ref   => [qw(ABCDE--F  GH--JK)],
        feat  => [qw(AB-DEWVF  -HUTJK)],
    },
    '02-basic' => {
        exons => [[1,5],[6,10]],
        ref   => [qw(ABCDE  --FGH--JK)],
        feat  => [qw(AB-DE  WVF-HUTJK)],
    },
    '03-basic' => {
        exons => [[1,5],[6,8],[9,10]],
        ref   => [qw(ABCDE  --FGH  --JK)],
        feat  => [qw(AB-DE  WVF-H  UTJK)],
    },
    );

foreach my $key (sort keys %exotests) {

    my $test_spec = $exotests{$key};
    compare_exon_split($vsa3, $test_spec, $key);
}

my %vsa_spec = (
    exons => [[1,251],[252,990]],
    ref   => [qw(
GATTGCTTGAGGAGAGAAGTATGTGATCAGAAAGCATTCTTTGTCTATTAACTCCTGCCCAGCAAAAGTGAAAGAAAATTCATGGGAGCATGCAAGAACAAAGAGCACAGCAAAGCTGGACAAACACAGCAATCCAGGCAGGGGATTTCCAACTCAACTCTGGTATATAAGCTGCATGCAAAGTCCTTTTTCTGTCTCTGGTTTCTGGCCCCTTGTCTGCAGAGATGGCTCCCAATGCTTCCTGCCTCTGT 

GTGCATGTCCGTTCCGAGGAATGGGATTTAATGACCTTTGATGCCAACCCATATGACAGCGTGAAAAAAATCAAAGAACATGTCCGGTCTAAGACCAAGGTTCCTGTGCAGGACCAGGTTCTTTTGCTGGGCTCCAAGATCTTAAAGCCACGGAGAAGCCTCTCATCTTACGGCATTGACAAAGAGAAGACCATCCACCTTACCCTGAAAGTGGTGAAGCCCAGTGATGAGGAGCTGCCCTTGTTTCTTGTGGAGTCAGGTGATGAGGCAAAGAGGCACCTCCTCCAGGTGCGAAGGTCCAGCTCAGTGGCACAAGTGAAAGCAATGATCGAGACTAAGACGGGTATAATCCCTGAGACCCAGATTGTGACTTGCAATGGAAAGAGACTGGAAGATGGGAAGATGATGGCAGATTACGGCATCAGAAAGGGCAACTTACTCTTCCTGGCATCTTATTGTATTGGAGGGTGACCACCCTGGGCATGGGGTGTTGGCAGGGGTCAAAAAGCTTATTTCTTTTAATCTCTTACTCAACGAACACATCTTCTGATGATTTCCCAAAATTAATGAGAATGAGATGAGTAGAGTAAGATTTGGGTGGGATGGGTAGGATGAAGTATATTGCCCAACTCTATGTTTCTTTGATTCTAACACAATTAA-TTAAGTGACATGATTTTTACTAATGTATTACTGAGACTAGTAAATAAATT--TTTAAGGCAAAA-TAGAGCA--TTCAAAGCCA
)],
    feat  => [qw(
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------GTCTGCAGAGATGGCTCCCAATGCTTCCTGCCTCTGT

GTGCATGTCCGTTCCGAGGAATGGGATTTAATGACCTTTGATGCCAACCCATATGACAGCGTGAAAAAAATCAAAGAACATGTCCGGTCTAAGACCAAGGTTCCTGTGCAGGACCAGGTTCTTTTGCTGGGCTCCAAGATCTTAAAGCCACGGAGAAGCCTCTCATCTTATGGCATTGACAAAGAGAAGACCATCCACCTTACCCTGAAAGTGGTGAAGCCCAGTGATGAGGAGCTGCCCTTGTTTCTTGTGGAGTCAGGTGATGAGGCAAAGAGGCACCTCCTCCAGGTGCGAAGGTCCAGCTCAGTGGCACAAGTGAAAGCAATGATCGAGACTAAGACGGGTATAATCCCTGAGACCCAGATTGTGACTTGCAATGGAAAGAGACTGGAAGATGGGAAGATGATGGCAGATTACGGCATCAGAAAGGGCAACTTACTCTTCCTGGCATCTTATTGTATTGGAGGGTGACCACCCTGGGCATGGGGTGTTGGCAGGGGTCAAAAAGCTTATTTCTTTTAATCTCTTACTCAACGAACACATCTTCTGATGATTTCCCAAAATTAATGAGAATGAGATGAGTAGAGTAAGATTTGGGTGGGATGGGTAGGATGAAGTATATTGCCCAACTCTATGTTTCTTTGATTCTAACACAATTAAGTTAAGTGACATGATTTTTACTAATGTATTACTGAGACTAGTACATAAATTTCTTAAAGGCAAAATTAGAGCAATTCCAAGGCCA
)],
    );

compare_exon_split($vsa, \%vsa_spec, 'vsa');

my%vsa2_spec = (
    exons => [[1,199],[200,411]],
    ref   => [qw(
GGCCTTATAACTGTTATCG-------------------CCA----------TCT-CGAAAAACGTGTG-CGGGTTTTTTTTTTTTTTTTTTGCTCCCAGCCTGCCCAGATTTCAGGAAGGAAAGAAGATCTTTTGCTTCTTCGGTCGCTGGGTCGGCTCTCCAGTGTCTGATGTTTACTGAAATCTTGATCGTGGTTAGCCTCCCCCAGGACTTCATTGTTTGGAAGATG

CCTTCGCCAAGCAATCTGAGCTCCAGGCCGGGAAGCCCCAAGGTCACAAATTTTAATGGAGCCCTGAAACTAAACAGAAATCATCCCTCCCACTAGAACAAGAGCCCCTAGAGGCCAGCGACACCGCTAAAATAACATGTGTAGACCAATGCCGTCCAGGTAACAGTGCCTGGCAAACACGGTAGAGGTTCAATAAATACATTTTAACTCAA
)],
    feat  => [qw(
GGCC------CTGGTTTCGGAATCGGGCTCCGGAACCCCCAATTGCCTTGTTCTCCGTAAAA-GTGTGCCGGGTTTTTTTTTTTTTTTTTTGCTCCCAGCCTGCCCAGATTTCAGGAAGGAAAGAAGATCTTTTGCTTCTTCGGTCGCTGGGTCGGCTCTCCAGTGTCTGATGTTTACTGAAATCTTGATCGTGGTTAGCCTCCCCCAGGACTTCATTGTTTGGAAGATG

CCTTCGCCAAGCAATCTGAGCTCCAGGCCGGGAAGCCCCAAGGTCACAAATTTTAATGGAGCCCTGAAACTAAACAGAAATCATCCCTCCCACTAGAACAAGAGCCCCTAGAGGCCAGCGACA-CGC-----------GAGTTG--------------------------------------------------------------------
)],
    );

compare_exon_split($vsa2, \%vsa2_spec, 'vsa2');

1;

# Supporting stuff - some copied from explore_evidence_for_transcripts.pl

sub compare_exon_split {
    my $align = shift;
    my $test_spec = shift;
    my $name = shift;

    my $exon_spec = $test_spec->{exons};
    my $n_exons = scalar @$exon_spec;

    my $exon_aligns = $align->split_exons($exon_spec);

    is( scalar @$exon_aligns, $n_exons, "$name - got $n_exons exon alignments");
    for my $e (0..1) {
        isa_ok($exon_aligns->[$e], 'Bio::Vega::SimpleAlign', "$name - alignment $e");
        is( $exon_aligns->[$e]->reference_seq->seq, $test_spec->{ref}->[$e],  "$name - ref seq alignment $e");
        is( $exon_aligns->[$e]->feature_seq->seq,   $test_spec->{feat}->[$e], "$name - feature seq alignment $e");
    }

    return;
}

{
    my $aligner;

    sub do_align {
        my $ref_seq    = shift;
        my $f_seq      = shift;
        my $do_reverse = shift;

        $aligner ||= Bio::Vega::Utils::Align->new;

        if ($do_reverse) {
            $f_seq = reverse_seq($f_seq);
        }

        my $results = $aligner->compare_feature_seqs_to_ref( $ref_seq, [ $f_seq ] );

        my $result = $results->[0];
        $result->direction( $do_reverse ? -1 : 1 );

        return $result;
    }
}

sub sequences {
    my %seq;

    # OTTHUMT00000077359, reverse strand
    $seq{OTTHUMT00000077359} = <<'__REFSEQ__';
GATTGCTTGAGGAGAGAAGTATGTGATCAGAAAGCATTCTTTGTCTATTAACTCCTGCCCAGCAAAAGTGAAAGAAAATTCATGGGAGCATGCAAGAACAAAGAGCACAGCAAAGCTGGACAAACACAGCAATCCAGGCAGGGGATTTCCAACTCAACTCTGGTATATAAGCTGCATGCAAAGTCCTTTTTCTGTCTCTGGTTTCTGGCCCCTTGTCTGCAGAGATGGCTCCCAATGCTTCCTGCCTCTGTGTGCATGTCCGTTCCGAGGAATGGGATTTAATGACCTTTGATGCCAACCCATATGACAGCGTGAAAAAAATCAAAGAACATGTCCGGTCTAAGACCAAGGTTCCTGTGCAGGACCAGGTTCTTTTGCTGGGCTCCAAGATCTTAAAGCCACGGAGAAGCCTCTCATCTTACGGCATTGACAAAGAGAAGACCATCCACCTTACCCTGAAAGTGGTGAAGCCCAGTGATGAGGAGCTGCCCTTGTTTCTTGTGGAGTCAGGTGATGAGGCAAAGAGGCACCTCCTCCAGGTGCGAAGGTCCAGCTCAGTGGCACAAGTGAAAGCAATGATCGAGACTAAGACGGGTATAATCCCTGAGACCCAGATTGTGACTTGCAATGGAAAGAGACTGGAAGATGGGAAGATGATGGCAGATTACGGCATCAGAAAGGGCAACTTACTCTTCCTGGCATCTTATTGTATTGGAGGGTGACCACCCTGGGCATGGGGTGTTGGCAGGGGTCAAAAAGCTTATTTCTTTTAATCTCTTACTCAACGAACACATCTTCTGATGATTTCCCAAAATTAATGAGAATGAGATGAGTAGAGTAAGATTTGGGTGGGATGGGTAGGATGAAGTATATTGCCCAACTCTATGTTTCTTTGATTCTAACACAATTAATTAAGTGACATGATTTTTACTAATGTATTACTGAGACTAGTAAATAAATTTTTAAGGCAAAATAGAGCATTCAAAGCCA
__REFSEQ__

    chomp($seq{OTTHUMT00000077359});

    # BI760949.1, 
    $seq{'BI760949.1'} = <<'__FEATSEQ__';
GTCTGCAGAGATGGCTCCCAATGCTTCCTGCCTCTGTGTGCATGTCCGTTCCGAGGAATGGGATTTAATGACCTTTGATGCCAACCCATATGACAGCGTGAAAAAAATCAAAGAACATGTCCGGTCTAAGACCAAGGTTCCTGTGCAGGACCAGGTTCTTTTGCTGGGCTCCAAGATCTTAAAGCCACGGAGAAGCCTCTCATCTTATGGCATTGACAAAGAGAAGACCATCCACCTTACCCTGAAAGTGGTGAAGCCCAGTGATGAGGAGCTGCCCTTGTTTCTTGTGGAGTCAGGTGATGAGGCAAAGAGGCACCTCCTCCAGGTGCGAAGGTCCAGCTCAGTGGCACAAGTGAAAGCAATGATCGAGACTAAGACGGGTATAATCCCTGAGACCCAGATTGTGACTTGCAATGGAAAGAGACTGGAAGATGGGAAGATGATGGCAGATTACGGCATCAGAAAGGGCAACTTACTCTTCCTGGCATCTTATTGTATTGGAGGGTGACCACCCTGGGCATGGGGTGTTGGCAGGGGTCAAAAAGCTTATTTCTTTTAATCTCTTACTCAACGAACACATCTTCTGATGATTTCCCAAAATTAATGAGAATGAGATGAGTAGAGTAAGATTTGGGTGGGATGGGTAGGATGAAGTATATTGCCCAACTCTATGTTTCTTTGATTCTAACACAATTAAGTTAAGTGACATGATTTTTACTAATGTATTACTGAGACTAGTACATAAATTTCTTAAAGGCAAAATTAGAGCAATTCCAAGGCCAGCTTGGAATTCTAATTCTGTCTTGGATACCTTGGTATTTTATGCCAAAAACTCCTATCTCCTTTCCTTTTATGACACGAGAAGTAGGTTGAGGGTTGGGATCCC
__FEATSEQ__

    # OTTHUMT00000077344, reverse strand
    $seq{OTTHUMT00000077344} = <<'__REFSEQ__';
GGCCTTATAACTGTTATCGCCATCTCGAAAAACGTGTGCGGGTTTTTTTTTTTTTTTTTTGCTCCCAGCCTGCCCAGATTTCAGGAAGGAAAGAAGATCTTTTGCTTCTTCGGTCGCTGGGTCGGCTCTCCAGTGTCTGATGTTTACTGAAATCTTGATCGTGGTTAGCCTCCCCCAGGACTTCATTGTTTGGAAGATGCCTTCGCCAAGCAATCTGAGCTCCAGGCCGGGAAGCCCCAAGGTCACAAATTTTAATGGAGCCCTGAAACTAAACAGAAATCATCCCTCCCACTAGAACAAGAGCCCCTAGAGGCCAGCGACACCGCTAAAATAACATGTGTAGACCAATGCCGTCCAGGTAACAGTGCCTGGCAAACACGGTAGAGGTTCAATAAATACATTTTAACTCAA
__REFSEQ__

    # BF376291.1 CM0-TN0038-100800-499-e11 TN0038 Homo sapiens cDNA, mRNA sequence.
    $seq{'BF376291.1'} = <<'__FEATSEQ__';
CTTTTTTCCCAGGGGAAAGCTTTGGCCCTGGTTTCGGAATCGGGCTCCGGAACCCCCAATTGCCTTGTTCTCCGTAAAAGTGTGCCGGGTTTTTTTTTTTTTTTTTTGCTCCCAGCCTGCCCAGATTTCAGGAAGGAAAGAAGATCTTTTGCTTCTTCGGTCGCTGGGTCGGCTCTCCAGTGTCTGATGTTTACTGAAATCTTGATCGTGGTTAGCCTCCCCCAGGACTTCATTGTTTGGAAGATGCCTTCGCCAAGCAATCTGAGCTCCAGGCCGGGAAGCCCCAAGGTCACAAATTTTAATGGAGCCCTGAAACTAAACAGAAATCATCCCTCCCACTAGAACAAGAGCCCCTAGAGGCCAGCGACACGCGAGTTG
__FEATSEQ__

    foreach my $key (keys %seq) {
        chomp($seq{$key});
    }

    return \%seq;
}

# Local Variables:
# mode: perl
# End:

# EOF
