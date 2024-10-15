#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::FeaturePair;

my $saf_protein_module;
BEGIN {
    $saf_protein_module = 'Bio::Vega::SplicedAlignFeature::Protein';
    use_ok($saf_protein_module);
}
critic_module_ok($saf_protein_module);

my $safd = new_ok($saf_protein_module => [ '-cigar_string' => '102M' ]);
is($safd->cigar_string, '102M', 'cigar_string');
is($safd->vulgar_comps_string, 'M 34 102', 'vulgar_comps_string');

# Knicked from EnsEMBL t.dnaPepAlignFeature.t

my $ctg_slice = OtterTest::ContigSlice->new->contig_slice;

my @fp_feats;
push @fp_feats, Bio::EnsEMBL::FeaturePair->new
  (-start  => 5,
   -end    => 7,
   -score  => 10,
   -strand => 1,
   -slice  => $ctg_slice,
   -hstart => 105,
   -hend   => 105,
   -hstrand => 1,
   -hseqname => 'dummy-hid');
push @fp_feats, Bio::EnsEMBL::FeaturePair->new
  (-start  => 11,
   -end    => 16,
   -score  => 10,
   -strand => 1,
   -slice  => $ctg_slice,
   -hstart => 106,
   -hend    => 107,
   -hstrand => 1,
   -hseqname => 'dummy-hid');

my $ddpaf = new_ok('Bio::Vega::DnaPepAlignFeature' => [ -features => \@fp_feats ]);

my @dp_feats;
push @dp_feats, $ddpaf;

my $dpaf = new_ok($saf_protein_module => [ -features => \@dp_feats ]);
is($dpaf->hseqname, 'dummy-hid', 'dpaf hseqname');
is($dpaf->cigar_string, '3M3I6M', 'dpaf cigar_string');

my @afs = $dpaf->as_AlignFeatures;
is(scalar(@afs), 1, 'one align_feature');
isa_ok($afs[0], 'Bio::Vega::DnaPepAlignFeature');
# FIXME: more tests here

$dpaf->seqname('ugf_test');
my @ungapped_features = $dpaf->ungapped_features;
is(scalar(@ungapped_features), 2, 'dpaf n-ungapped_features');
my $ugf_exp = {
    package => 'Bio::EnsEMBL::FeaturePair',
    strand  => 1,
    hstrand => 1,
    hseqname => 'dummy-hid',
    seqname => 'ugf_test',
    exons    => [
        { start =>  5, end =>  7, hstart => 105, hend => 105 },
        { start => 11, end => 16, hstart => 106, hend => 107 },
        ],
};
test_exons(\@ungapped_features, $ugf_exp, 'dpaf ungapped_features');

# Yuck, a lot of this is copied and mashed from OtterGappedAlignment.t

my $vcs = 'M 274 822 I 0 2246 M 11 33 F 0 1 M 52 156 G 25 0 M 1 3 I 0 1312 M 18 54 F 0 1 G 1 0 M 36 108 S 0 2 I 0 8901 S 1 1 M 76 228 S 0 1 I 0 3913 S 1 2 M 51 153 S 0 1 I 0 762 S 1 2 M 26 78 I 0 603 M 91 273';
my $v_string = 'QueryP 0 665 . TargetP 152 19808 + 3047 ' . $vcs;

$safd = new_ok($saf_protein_module => [ -vulgar_string => $v_string ], 'new from vulgar_string');
is($safd->vulgar_comps_string, $vcs, 'vulgar_comps_string');

note 'Expect warning "Intron info will be lost..."';
is($safd->cigar_string, '822M2246I33MI156M75D3M1312I54MI3D108M8903I229M3914I155M763I80M603I273M', 'cigar_string');
is($safd->hseqname,  'QueryP', 'hseqname');
is($safd->hstart,          1, 'hstart');
is($safd->hend,          665, 'hend');
is($safd->hstrand,         1, 'hstrand');
is($safd->seqname,  'TargetP', 'seqname');
is($safd->start,         153, 'start');
is($safd->end,         19808, 'end');
is($safd->strand,          1, 'strand');
is($safd->score,        3047, 'score');

$safd->slice($ctg_slice);
$safd->percent_id(78.9);

is($safd->to_gff(gff_args()), <<'__EO_GFF__', 'safd GFF');
AL359765.6.1.13780	VSAF_test	protein_match	153	974	3047.000000	+	.	Name=QueryP;Target=QueryP 1 274 +;cigar_ensembl=822M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	3221	3253	3047.000000	+	.	Name=QueryP;Target=QueryP 275 285 +;cigar_ensembl=33M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	3255	3413	3047.000000	+	.	Name=QueryP;Target=QueryP 286 363 +;cigar_ensembl=156M75D3M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	4726	4779	3047.000000	+	.	Name=QueryP;Target=QueryP 364 381 +;cigar_ensembl=54M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	4781	4888	3047.000000	+	.	Name=QueryP;Target=QueryP 383 418 +;cigar_ensembl=108M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	13793	14020	3047.000000	+	.	Name=QueryP;Target=QueryP 420 495 +;cigar_ensembl=228M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	17937	18089	3047.000000	+	.	Name=QueryP;Target=QueryP 497 547 +;cigar_ensembl=153M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	18855	18932	3047.000000	+	.	Name=QueryP;Target=QueryP 549 574 +;cigar_ensembl=78M;percentID=78.9
AL359765.6.1.13780	VSAF_test	protein_match	19536	19808	3047.000000	+	.	Name=QueryP;Target=QueryP 575 665 +;cigar_ensembl=273M;percentID=78.9
__EO_GFF__

my @exons = $safd->get_all_exon_alignments;
is(scalar(@exons), 7, 'n_exons');
my $exp = {
    exons => [
        { start =>   153, end =>   974, hstart =>   1, hend => 274, phase => 0, end_phase => 0, vcs => 'M 274 822' },
        { start =>  3221, end =>  3413, hstart => 275, hend => 363, phase => 0, end_phase => 0, vcs => 'M 11 33 F 0 1 M 52 156 G 25 0 M 1 3' },
        { start =>  4726, end =>  4890, hstart => 364, hend => 418, phase => 0, end_phase => 2, vcs => 'M 18 54 F 0 1 G 1 0 M 36 108 S 0 2' },
        { start => 13792, end => 14021, hstart => 419, hend => 495, phase => 2, end_phase => 1, vcs => 'S 1 1 M 76 228 S 0 1' },
        { start => 17935, end => 18090, hstart => 496, hend => 547, phase => 1, end_phase => 1, vcs => 'S 1 2 M 51 153 S 0 1' },
        { start => 18853, end => 18932, hstart => 548, hend => 574, phase => 1, end_phase => 0, vcs => 'S 1 2 M 26 78',
          vulgar_string => 'QueryP 547 574 . TargetP 18852 18932 + 3047 S 1 2 M 26 78' },
        { start => 19536, end => 19808, hstart => 575, hend => 665, phase => 0, end_phase => 0, vcs => 'M 91 273' },
        ],
    strand   => 1,
    hstrand  => 1,
    seqname  => 'TargetP',
    hseqname => 'QueryP',
    package  => $saf_protein_module,
};
test_exons(\@exons, $exp, 'get_all_exon_alignments (fwd)');

my @introns = $safd->get_all_introns;
is(scalar(@introns), 6, 'n_introns');
test_introns(\@introns, $exp, 'get_all_introns (fwd)');

my @pafs = map { $_->as_AlignFeatures } @exons;
my $rebuilt = new_ok($saf_protein_module => [ -features => \@pafs ]);
compare_saf_ok($rebuilt, $safd, 'new from features (fwd)', [ 'vulgar_comps_string' ]);
$vcs = $safd->vulgar_comps_string;
$vcs =~ s/S 0 2 I 0 8901 S 1 1/I 0 8904 G 1 0/; # fix up 1st split codon
$vcs =~ s/S 0 1 I 0 3913 S 1 2/I 0 3916 G 1 0/; # fix up 2nd split codon
$vcs =~ s/S 0 1 I 0 762 S 1 2/I 0 765 G 1 0/;   # fix up 3rd split codon
is($rebuilt->vulgar_comps_string, $vcs, 'rebuilt vulgar comps');

$vcs = $safd->vulgar_comps_string; # save for new() below

$safd->reverse_complement;
is($safd->cigar_string,
   '273M603I80M763I155M3914I229M8903I108M3DI54M1312I3M75D156MI33M2246I822M',
   'cigar_string (rev_comp)');
is($safd->vulgar_comps_string,
   'M 91 273 I 0 603 M 26 78 S 1 2 I 0 762 S 0 1 M 51 153 S 1 2 I 0 3913 S 0 1 M 76 228 S 1 1 I 0 8901 S 0 2 M 36 108 G 1 0 F 0 1 M 18 54 I 0 1312 M 1 3 G 25 0 M 52 156 F 0 1 M 11 33 I 0 2246 M 274 822',
   'vulgar_comps_string (rev_comp)');
is ($safd->strand,  -1, 'strand  (rev_comp)');
is ($safd->hstrand,  1, 'hstrand (rev_comp)');

$safd = new_ok($saf_protein_module => [ -vulgar_comps_string => $vcs ], 'new from vulgar_comps_string');
$safd->seqname('TRev');
$safd->start(35467);
$safd->end(55122);
$safd->strand(-1);
$safd->hseqname('QRev');
$safd->hstart(1);
$safd->hend(665);
$safd->slice($ctg_slice);

note 'Expect warning "Intron info will be lost..."';
is($safd->cigar_string, '822M2246I33MI156M75D3M1312I54MI3D108M8903I229M3914I155M763I80M603I273M', 'cigar_string');

my @r_exons = $safd->get_all_exon_alignments;
is(scalar(@r_exons), 7, 'n_exons (rev)');

# Mangle $exp as necessary
$exp->{exons}->[0]->{start} = 54301; $exp->{exons}->[0]->{end} = 55122;
$exp->{exons}->[1]->{start} = 51862; $exp->{exons}->[1]->{end} = 52054;
$exp->{exons}->[2]->{start} = 50385; $exp->{exons}->[2]->{end} = 50549;
$exp->{exons}->[3]->{start} = 41254; $exp->{exons}->[3]->{end} = 41483;
$exp->{exons}->[4]->{start} = 37185; $exp->{exons}->[4]->{end} = 37340;
$exp->{exons}->[5]->{start} = 36343; $exp->{exons}->[5]->{end} = 36422;
$exp->{exons}->[5]->{vulgar_string} = 'QRev 547 574 . TRev 36422 36342 - 0 S 1 2 M 26 78';
$exp->{exons}->[6]->{start} = 35467; $exp->{exons}->[6]->{end} = 35739;
$exp->{strand} = -1;
$exp->{seqname} = 'TRev';
$exp->{hseqname} = 'QRev';

test_exons(\@r_exons, $exp, 'get_all_exon_alignments (rev)');

my @r_introns = $safd->get_all_introns;
is(scalar(@r_introns), 6, 'n_introns');
test_introns(\@r_introns, $exp, 'get_all_introns (rev)');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
