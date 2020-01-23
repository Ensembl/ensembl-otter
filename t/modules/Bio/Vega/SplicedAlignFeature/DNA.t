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

use Test::More;
use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::Otter;
use OtterTest::ContigSlice;
use Test::VegaSplicedAlignFeature qw(test_exons test_introns compare_saf_ok gff_args);

use Bio::Vega::DnaDnaAlignFeature;
use Bio::EnsEMBL::FeaturePair;

my $saf_dna_module;
BEGIN {
    $saf_dna_module = 'Bio::Vega::SplicedAlignFeature::DNA';
    use_ok($saf_dna_module);
}
critic_module_ok($saf_dna_module);

my $safd = new_ok($saf_dna_module => [ '-cigar_string' => '100M' ]);
is($safd->cigar_string, '100M', 'cigar_string');
is($safd->vulgar_comps_string, 'M 100 100', 'vulgar_comps_string');

# Knicked from EnsEMBL t.dnaDnaAlignFeature.t

my $ctg_slice = OtterTest::ContigSlice->new->contig_slice;

my @fp_feats;
push @fp_feats, Bio::EnsEMBL::FeaturePair->new
  (-START => 5,
   -END   => 7,
   -STRAND => 1,
   -SCORE => 10,
   -SLICE => $ctg_slice,
   -HSTART => 105,
   -HEND   => 107,
   -HSTRAND => 1,
   -HSEQNAME => 'dummy-hid');

push @fp_feats, Bio::EnsEMBL::FeaturePair->new
  (-start   => 10,
   -end     => 14,
   -strand  => 1,
   -score   => 10,
   -slice   => $ctg_slice,
   -hstart  => 108,
   -hend    => 112,
   -hstrand => 1,
   -hseqname => 'dummy-hid');

my $ddaf = new_ok('Bio::Vega::DnaDnaAlignFeature' => [ -features => \@fp_feats ]);

my @dd_feats;
push @dd_feats, $ddaf;

my $dnaf = new_ok($saf_dna_module => [ -features => \@dd_feats ]);
is($dnaf->hseqname, 'dummy-hid', 'dnaf hseqname');
is($dnaf->cigar_string, '3M2I5M', 'dnaf cigar_string');

my $strand = $dnaf->strand;
my $hstrand = $dnaf->hstrand;
$dnaf->reverse_complement;
is($dnaf->cigar_string, '5M2I3M', 'dnaf reverse_complement cigar_string');
is($dnaf->strand,  $strand  * -1, 'dnaf reverse_complement strand');
is($dnaf->hstrand, $hstrand * -1, 'dnaf reverse_complement hstrand');

is($dnaf->start, 5, 'dnaf start');
is($dnaf->end,  14, 'dnaf end');

$dnaf->percent_id(58.3);
is($dnaf->to_gff(gff_args()), <<'__EO_GFF__', 'dnaf GFF');
AL359765.6.1.13780	VSAF_test	nucleotide_match	5	14	10.000000	-	.	Name=dummy-hid;Target=dummy-hid 105 112 -;cigar_ensembl=5M2I3M;percentID=58.3
__EO_GFF__

my @afs = $dnaf->as_AlignFeatures;
is(scalar(@afs), 1, 'one align_feature');
isa_ok($afs[0], 'Bio::Vega::DnaDnaAlignFeature');
# FIXME: more tests here

$dnaf->seqname('ugf_test');
my @ungapped_features = $dnaf->ungapped_features;
is(scalar(@ungapped_features), 2, 'dnaf n-ungapped_features');
my $ugf_exp = {
    package => 'Bio::EnsEMBL::FeaturePair',
    strand  => $strand * -1,
    hstrand => $hstrand * -1,
    hseqname => 'dummy-hid',
    seqname => 'ugf_test',
    exons    => [
        { start => 10, end => 14, hstart => 108, hend => 112 },
        { start =>  5, end =>  7, hstart => 105, hend => 107 },
        ],
};
test_exons(\@ungapped_features, $ugf_exp, 'dnaf ungapped_features');

my $v_string = 'Query 0 20 + Target 21 6 - 56 M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0';
$safd = new_ok($saf_dna_module => [ -vulgar_string => $v_string ], 'new from vulgar_string');
is($safd->vulgar_comps_string, 'M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0', 'vulgar_comps_string');
is($safd->cigar_string, '5M3D5MI4M3D', 'cigar_string');
is($safd->hseqname,  'Query', 'hseqname');
is($safd->hstart,          1, 'hstart');
is($safd->hend,           20, 'hend');
is($safd->hstrand,         1, 'hstrand');
is($safd->seqname,  'Target', 'seqname');
is($safd->start,           7, 'start');
is($safd->end,            21, 'end');
is($safd->strand,         -1, 'strand');
is($safd->score,          56, 'score');

my $v_obj = Bio::Otter::Vulgar->new($v_string);
my $v_safd = new_ok($saf_dna_module => [ -vulgar => $v_obj ], 'new from vulgar object');
compare_saf_ok($v_safd, $safd, 'matches from vulgar_string');

my $vcs = 'M 3 3 I 0 43 M 2 2 G 3 0 M 4 4 I 0 44 M 1 1 G 0 1 M 1 1 I 0 42 M 3 3 G 3 0';
$safd = new_ok($saf_dna_module => [ -vulgar_comps_string => $vcs ], 'new from vulgar_comps_string');
is($safd->vulgar_comps_string, $vcs, 'vulgar_comps_string');
note 'Expect warning "Intron info will be lost..."';
is($safd->cigar_string, '3M43I2M3D4M44IMIM42I3M3D', 'cigar_string');

$safd->start(23234);
$safd->end(23377);
$safd->hstart(1);
$safd->hend(20);
$safd->seqname('Tseq');
$safd->hseqname('Qseq');
$safd->slice($ctg_slice);
$safd->percent_id(67.8);

is($safd->to_gff(gff_args()), <<'__EO_GFF__', 'safd GFF');
AL359765.6.1.13780	VSAF_test	nucleotide_match	23234	23236	.	+	.	Name=Qseq;Target=Qseq 1 3 +;cigar_ensembl=3M;percentID=67.8
AL359765.6.1.13780	VSAF_test	nucleotide_match	23280	23285	.	+	.	Name=Qseq;Target=Qseq 4 12 +;cigar_ensembl=2M3D4M;percentID=67.8
AL359765.6.1.13780	VSAF_test	nucleotide_match	23330	23332	.	+	.	Name=Qseq;Target=Qseq 13 14 +;cigar_ensembl=MIM;percentID=67.8
AL359765.6.1.13780	VSAF_test	nucleotide_match	23375	23377	.	+	.	Name=Qseq;Target=Qseq 15 17 +;cigar_ensembl=3M;percentID=67.8
__EO_GFF__

my @exons = $safd->get_all_exon_alignments;
is(scalar(@exons), 4, 'n_exons');
my $exp = {
    exons => [
        { start => 23234, end => 23236, hstart =>  1, hend =>  3, vcs => 'M 3 3' },
        { start => 23280, end => 23285, hstart =>  4, hend => 12, vcs => 'M 2 2 G 3 0 M 4 4',
          vulgar_string => 'Qseq 3 12 + Tseq 23279 23285 + 0 M 2 2 G 3 0 M 4 4'},
        { start => 23330, end => 23332, hstart => 13, hend => 14, vcs => 'M 1 1 G 0 1 M 1 1' },
        { start => 23375, end => 23377, hstart => 15, hend => 20, vcs => 'M 3 3 G 3 0' },
        ],
    strand  => 1,
    hstrand => 1,
    seqname => 'Tseq',
    hseqname => 'Qseq',
    package  => $saf_dna_module,
};
test_exons(\@exons, $exp, 'get_all_exon_alignments (fwd)');

my @introns = $safd->get_all_introns;
is(scalar(@introns), 3, 'n_introns');
test_introns(\@introns, $exp, 'get_all_introns (fwd)');

my @dafs = map { $_->as_AlignFeatures } @exons;
my $rebuilt = new_ok($saf_dna_module => [ -features => \@dafs ]);
compare_saf_ok($rebuilt, $safd, 'new from features (fwd)', [ qw(hend vulgar_comps_string) ]);
is($rebuilt->hend, $safd->hend - 3, 'rebuilt hend');
is($rebuilt->vulgar_comps_string, substr($safd->vulgar_comps_string, 0, -6), 'rebuilt vulgar comps');

$safd->strand(1);
$safd->hstrand(1);
$safd->reverse_complement;
is($safd->cigar_string, '3D3M42IMIM44I4M3D2M43I3M', 'cigar_string (rev_comp)');
is($safd->vulgar_comps_string, 'G 3 0 M 3 3 I 0 42 M 1 1 G 0 1 M 1 1 I 0 44 M 4 4 G 3 0 M 2 2 I 0 43 M 3 3',
   'vulgar_comps_string (rev_comp)');
is ($safd->strand,  -1, 'strand  (rev_comp)');
is ($safd->hstrand, -1, 'hstrand (rev_comp)');

# Copied from OtterGappedAlignment.t
# not sure about target strand!
my $vulgar = 'BG212959.1 928 0 - RP1-90J20.6-002 91513 84135 - 3570 M 9 9 G 0 1 M 3 3 G 0 3 M 6 6 G 0 4 I 0 814 M 11 11 G 0 2 M 6 6 G 0 3 M 4 4 G 0 1 M 1 1 G 0 1 M 4 4 G 0 1 M 1 1 G 0 1 M 2 2 G 0 1 M 10 10 G 0 1 M 3 3 G 0 1 M 5 5 G 0 1 M 2 2 G 0 1 M 4 4 G 0 1 M 3 3 G 0 1 M 6 6 G 0 2 M 6 6 G 0 1 M 6 6 G 0 1 M 10 10 G 0 1 M 5 5 G 0 1 M 3 3 G 0 1 M 3 3 I 0 1405 M 7 7 G 0 2 M 20 20 G 0 1 M 3 3 G 0 1 M 9 9 G 0 1 M 6 6 G 0 1 M 10 10 G 0 1 M 7 7 G 1 0 M 4 4 G 0 1 M 57 57 G 0 1 M 11 11 I 0 3974 M 9 9 G 0 1 M 17 17 G 0 1 M 9 9 G 0 1 M 7 7 G 0 1 M 8 8 G 1 0 M 15 15 G 0 1 M 86 86 I 0 214 M 528 528';

$safd = new_ok($saf_dna_module => [ -vulgar_string => $vulgar ], 'new from vulgar_string 2');
is($safd->hseqname, 'BG212959.1',      'hseqname');
is($safd->hstart,                   1, 'hstart');
is($safd->hend,                   928, 'hend');
is($safd->hstrand,                 -1, 'hstrand');
is($safd->seqname,  'RP1-90J20.6-002', 'seqname');
is($safd->start,                84136, 'start');
is($safd->end,                  91513, 'end');
is($safd->strand,                  -1, 'strand');
is($safd->score,                 3570, 'score');

# Ensure pass-through
$safd->species('9000');
$safd->hspecies('9001');
$safd->coverage(53);
$safd->hcoverage(63);
$safd->percent_id(97.7);
$safd->p_value(1.33e-07);
# $safd->analysis(445); # FIXME: need Analysis object
$safd->external_db_id(10023);
$safd->extra_data('Answer_42');

$safd->slice($ctg_slice);
my @r_exons = $safd->get_all_exon_alignments;
is(scalar(@r_exons), 5, 'n_exons');
my $r_exp = {
    exons => [
        { start => 91488, end => 91513, hstart => 911, hend => 928,
          vcs => 'M 9 9 G 0 1 M 3 3 G 0 3 M 6 6 G 0 4',
        },
        { start => 90556, end => 90673, hstart => 816, hend => 910,
          vcs => 'M 11 11 G 0 2 M 6 6 G 0 3 M 4 4 G 0 1 M 1 1 G 0 1 M 4 4 G 0 1 M 1 1 G 0 1 M 2 2 G 0 1 M 10 10 G 0 1 M 3 3 G 0 1 M 5 5 G 0 1 M 2 2 G 0 1 M 4 4 G 0 1 M 3 3 G 0 1 M 6 6 G 0 2 M 6 6 G 0 1 M 6 6 G 0 1 M 10 10 G 0 1 M 5 5 G 0 1 M 3 3 G 0 1 M 3 3',
        },
        { start => 89008, end => 89150, hstart => 681, hend => 815,
          vcs => 'M 7 7 G 0 2 M 20 20 G 0 1 M 3 3 G 0 1 M 9 9 G 0 1 M 6 6 G 0 1 M 10 10 G 0 1 M 7 7 G 1 0 M 4 4 G 0 1 M 57 57 G 0 1 M 11 11',
        },
        { start => 84878, end => 85033, hstart => 529, hend => 680,
          vcs => 'M 9 9 G 0 1 M 17 17 G 0 1 M 9 9 G 0 1 M 7 7 G 0 1 M 8 8 G 1 0 M 15 15 G 0 1 M 86 86',
        },
        { start => 84136, end => 84663, hstart =>   1, hend => 528,
          vcs => 'M 528 528',
        },
        ],
    strand   => -1,
    hstrand  => -1,
    seqname  => 'RP1-90J20.6-002',
    hseqname => 'BG212959.1',
    package  => $saf_dna_module,
};
test_exons(\@r_exons, $r_exp, 'get_all_exon_alignments (rev)');

my @r_introns = $safd->get_all_introns;
is(scalar(@r_introns), 4, 'n_introns');
test_introns(\@r_introns, $r_exp, 'get_all_introns (rev)');

my @r_dafs = map { $_->as_AlignFeatures } @r_exons;
my $r_rebuilt = new_ok($saf_dna_module => [ -features => \@r_dafs ]);
compare_saf_ok($r_rebuilt, $safd, 'new from features (rev/rev)', [ 'vulgar_comps_string' ]);
$vcs = $safd->vulgar_comps_string;
$vcs =~ s/G 0 4 I 0 814/I 0 818/; # remove exon trailing indel
is($r_rebuilt->vulgar_comps_string, $vcs, 'rebuilt vulgar comps');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
