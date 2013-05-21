#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::Otter;
use OtterTest::ContigSlice;
use Test::VegaSplicedAlignFeature qw(test_exons test_introns);

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

my @feats;
push @feats, Bio::EnsEMBL::FeaturePair->new
  (-start  => 5,
   -end    => 7,
   -score  => 10,
   -strand => 1,
   -slice  => $ctg_slice,
   -hstart => 105,
   -hend   => 105,
   -hstrand => 1,
   -hseqname => 'dummy-hid');
push @feats, Bio::EnsEMBL::FeaturePair->new
  (-start  => 11,
   -end    => 16,
   -score  => 10,
   -strand => 1,
   -slice  => $ctg_slice,
   -hstart => 106,
   -hend    => 107,
   -hstrand => 1,
   -hseqname => 'dummy-hid');

my $dpaf = new_ok($saf_protein_module => [ -features => \@feats ]);
is($dpaf->hseqname, 'dummy-hid', 'dpaf hseqname');
is($dpaf->cigar_string, '3M3I6M', 'dpaf cigar_string');

my $strand = $dpaf->strand;
my $hstrand = $dpaf->hstrand;
$dpaf->reverse_complement;
is($dpaf->cigar_string, '6M3I3M', 'dpaf reverse_complement cigar_string');
is($dpaf->strand,  $strand  * -1, 'dpaf reverse_complement strand');
is($dpaf->hstrand, $hstrand * -1, 'dpaf reverse_complement hstrand');

is($dpaf->start, 5, 'dpaf start');
is($dpaf->end,  16, 'dpaf end');

SKIP: {
    skip('ungapped_features not implemented for SplicedAlignFeatures yet.', 1);
    is(scalar($dpaf->ungapped_features), 2, 'dpaf n-ungapped_features');
}

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
my @exons = $safd->get_all_exon_alignments;
is(scalar(@exons), 7, 'n_exons');
my $exp = {
    exons => [
        { start =>   153, end =>   974, hstart =>   1, hend => 274, phase => 0, end_phase => 0, vcs => 'M 274 822' },
        { start =>  3221, end =>  3413, hstart => 275, hend => 363, phase => 0, end_phase => 0, vcs => 'M 11 33 F 0 1 M 52 156 G 25 0 M 1 3' },
        { start =>  4726, end =>  4890, hstart => 364, hend => 418, phase => 0, end_phase => 2, vcs => 'M 18 54 F 0 1 G 1 0 M 36 108 S 0 2' },
        { start => 13792, end => 14021, hstart => 419, hend => 495, phase => 2, end_phase => 1, vcs => 'S 1 1 M 76 228 S 0 1' },
        { start => 17935, end => 18090, hstart => 496, hend => 547, phase => 1, end_phase => 1, vcs => 'S 1 2 M 51 153 S 0 1' },
        { start => 18853, end => 18932, hstart => 548, hend => 574, phase => 1, end_phase => 0, vcs => 'S 1 2 M 26 78' },
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
