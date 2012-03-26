#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use CriticModule;

use Readonly;
use Scalar::Util qw(reftype);
use Test::More;

use Log::Log4perl qw(:easy);
my $level = $ENV{HARNESS_IS_VERBOSE} ? $DEBUG : $WARN;
Log::Log4perl->easy_init({ level => $level, file => 'stdout', layout => '# %p: %m%n' });

use Hum::Ace::SubSeq;

Readonly my %ele_expected => {
    'M' => { class => 'Match',      desc => 'match',                   q => 10, t => 10 },
    'C' => { class => 'Codon',      desc => 'codon',                   q => 10, t => 10 },
    'G' => { class => 'Gap',        desc => 'gap',                     q => 10, t =>  0 },
    'N' => { class => 'NER',        desc => 'non-equivalenced region', q => 10, t => 10 },
    '5' => { class => 'SS_5P',      desc => "5' splice site",          q => 10, t => 10 },
    '3' => { class => 'SS_3P',      desc => "3' splice site",          q => 10, t => 10 },
    'I' => { class => 'Intron',     desc => 'intron',                  q => 10, t => 10 },
    'S' => { class => 'SplitCodon', desc => 'split codon',             q => 10, t => 10 },
    'F' => { class => 'Frameshift', desc => 'frameshift',              q => 10, t => 10 },
};

my ($ele_module, $ga_module);
BEGIN {
    $ga_module = 'Bio::Otter::GappedAlignment';
    use_ok($ga_module);
    $ele_module = 'Bio::Otter::GappedAlignment::Element';
    use_ok($ele_module);
}

critic_module_ok($ga_module);
critic_module_ok($ele_module);
critic_module_ok($ga_module . '::ElementI');
critic_module_ok($ga_module . '::ElementTypes');

foreach my $type (keys %ele_expected) {
    my $exp = $ele_expected{$type};
    my $ele = $ele_module->new($type, $exp->{q}, $exp->{t});
    my $class = $ele_module . '::' . $exp->{class};
    isa_ok($ele, $class);
    is($ele->type, $type, "type for $type");
    is($ele->long_type, $exp->{desc}, "long_type for $type");
    critic_module_ok($class);
}

Readonly my %tiny_ts_expected => (

    vulgar   => 'Q 0 20 + T 6 21 + 56 M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0',

    q_id     => 'Q',
    q_start  => 0,
    q_end    => 20,
    q_strand => '+',
    t_id     => 'T',
    t_start  => 6,
    t_end    => 21,
    t_strand => '+',
    score    => 56,
    n_ele    => 6,

    intron_vulgar  => 'M 3 3 I 0 3 M 2 2 G 3 0 M 4 4 I 0 4 M 1 1 G 0 1 M 1 1 I 0 2 M 3 3 G 3 0',
    intron_n_ele   => 12,
    );

# Common expected components for test clone results
#
my %test_clone_exp = (         # not Readonly as some components manufactured from others

    invariants => {
        t_id         => 'EMBOSS_001',
        score        => 12625,
        n_ele        => 5,
        intron_n_ele => 17,
    },

    ts_vulgar_comps_fwd => 'M 1007 1007 G 0 1 M 214 214 G 2 0 M 1315 1315',
    ts_vulgar_comps_rev => 'M 1315 1315 G 2 0 M 214 214 G 0 1 M 1007 1007',

    intronified_vulgar_comps_fwd  => 'M 974 974 I 0 2246 M 33 33 G 0 1 M 159 159 I 0 1312 M 55 55 G 2 0 M 110 110 I 0 8901 M 230 230 I 0 3913 M 156 156 I 0 762 M 80 80 I 0 603 M 739 739',

    intronified_vulgar_comps_rev  => 'M 739 739 I 0 603 M 80 80 I 0 762 M 156 156 I 0 3913 M 230 230 I 0 8901 M 110 110 G 2 0 M 55 55 I 0 1312 M 159 159 G 0 1 M 33 33 I 0 2246 M 974 974',

    exons_fwd_region => [
        [ 120389, 121362 ],
        [ 123609, 123801 ],
        [ 125114, 125278 ],
        [ 134180, 134409 ],
        [ 138323, 138478 ],
        [ 139241, 139320 ],
        [ 139924, 140662 ],
    ],

    fwd_region_min   => 120389,
    fwd_region_v_min => 120389 - 1,
    fwd_region_max   => 140662,

    exons_rev_region => [
        [ 35001, 35739 ],
        [ 36343, 36422 ],
        [ 37185, 37340 ],
        [ 41254, 41483 ],
        [ 50385, 50549 ],
        [ 51862, 52054 ],
        [ 54301, 55274 ],
    ],
    rev_region_min   => 35001,
    rev_region_v_min => 35001 - 1,
    rev_region_max   => 55274,

    v_fwd_query_exons_fwd => [
        [    0,  974 ],
        [  974, 1166 ],
        [ 1166, 1333 ],
        [ 1333, 1563 ],
        [ 1563, 1719 ],
        [ 1719, 1799 ],
        [ 1799, 2538 ],
    ],

    v_rev_query_exons_fwd => [
        [   15,  754 ],
        [  754,  834 ],
        [  834,  990 ],
        [  990, 1220 ],
        [ 1220, 1387 ],
        [ 1387, 1579 ],
        [ 1579, 2553 ],
    ],

    exon_vulgars_fwd => [
        'M 974 974',
        'M 33 33 G 0 1 M 159 159',
        'M 55 55 G 2 0 M 110 110',
        'M 230 230',
        'M 156 156',
        'M 80 80',
        'M 739 739',
    ],

    exon_vulgars_rev => [
        'M 739 739',
        'M 80 80',
        'M 156 156',
        'M 230 230',
        'M 110 110 G 2 0 M 55 55',
        'M 159 159 G 0 1 M 33 33',
        'M 974 974',
    ],
    );

$test_clone_exp{v_exons_fwd_region} = adjust_start_coords($test_clone_exp{exons_fwd_region}, -1);
$test_clone_exp{v_exons_rev_region} = adjust_start_coords($test_clone_exp{exons_rev_region}, -1);

$test_clone_exp{v_exons_fwd_region_revd} = reverse_exon_coords($test_clone_exp{v_exons_fwd_region});
$test_clone_exp{v_exons_rev_region_revd} = reverse_exon_coords($test_clone_exp{v_exons_rev_region});

$test_clone_exp{v_fwd_query_exons_rev} = reverse_exon_coords($test_clone_exp{v_fwd_query_exons_fwd});
$test_clone_exp{v_rev_query_exons_rev} = reverse_exon_coords($test_clone_exp{v_rev_query_exons_fwd});

Readonly my @split_expected => (
    {
        name     => 'Tiny fwd',
        %tiny_ts_expected,

        ts_strand => 1,
        exons     => [ [21, 24], [27, 31], [35, 40], [45, 47], [50,52] ],
        clone_contig_offset => 0,

        intron_t_start => 28,
        intron_t_end   => 52,
        intron_t_strand=> '+',

        splits => [
            'Q 0 3 + T 28 31 + 0 M 3 3',
            'Q 3 12 + T 34 40 + 0 M 2 2 G 3 0 M 4 4',
            'Q 12 14 + T 44 47 + 0 M 1 1 G 0 1 M 1 1',
            'Q 14 20 + T 49 52 + 0 M 3 3 G 3 0',
            ],
    },
    {
        name     => 'Tiny rev',
        %tiny_ts_expected,

        ts_strand => -1,
        exons     => [ [56, 58], [61, 63], [68, 73], [77, 81], [84, 87] ],
        clone_contig_offset => 0,

        intron_t_start => 79,
        intron_t_end   => 55,
        intron_t_strand=> '-',

        splits => [
            'Q 0 3 + T 79 76 - 0 M 3 3',
            'Q 3 12 + T 73 67 - 0 M 2 2 G 3 0 M 4 4',
            'Q 12 14 + T 63 60 - 0 M 1 1 G 0 1 M 1 1',
            'Q 14 20 + T 58 55 - 0 M 3 3 G 3 0',
            ],
    },
    {
        name     => 'RP11-420G6.2-002 vs BC018923.2',
        vulgar   => 'BC018923.2 0 2538 + ENST00000380771 57 2595 + 12663 M 2538 2538',

        q_id     => 'BC018923.2',
        q_start  => 0,
        q_end    => 2538,
        q_strand => '+',
        t_id     => 'ENST00000380771',
        t_start  => 57,
        t_end    => 2595,
        t_strand => '+',
        score    => 12663,
        n_ele    => 1,

        ts_strand => 1,
        exons     => [
            [ 69325, 70355 ],
            [ 72602, 72793 ],
            [ 74106, 74272 ],
            [ 83174, 83403 ],
            [ 87317, 87472 ],
            [ 88235, 88314 ],
            [ 88918, 89656 ],
            ],
        clone_contig_offset => 100,    # contig starts at bp 100 in clone; ts is rel contig

        intron_vulgar  => 'M 974 974 I 0 2246 M 192 192 I 0 1312 M 167 167 I 0 8901 M 230 230 I 0 3913 M 156 156 I 0 762 M 80 80 I 0 603 M 739 739',
        intron_t_start => 69481,
        intron_t_end   => 89756,
        intron_t_strand=> '+',
        intron_n_ele   => 13,

        splits => [
            'BC018923.2 0 974 + ENST00000380771 69481 70455 + 0 M 974 974',
            'BC018923.2 974 1166 + ENST00000380771 72701 72893 + 0 M 192 192',
            'BC018923.2 1166 1333 + ENST00000380771 74205 74372 + 0 M 167 167',
            'BC018923.2 1333 1563 + ENST00000380771 83273 83503 + 0 M 230 230',
            'BC018923.2 1563 1719 + ENST00000380771 87416 87572 + 0 M 156 156',
            'BC018923.2 1719 1799 + ENST00000380771 88334 88414 + 0 M 80 80',
            'BC018923.2 1799 2538 + ENST00000380771 89017 89756 + 0 M 739 739'
            ],
    },
    {
        name     => 'RP11-420G6.1-003 vs BI831275.1',
        vulgar   => 'BI831275.1 0 746 + OTTHUMT00000039637 57 797 + 3471 M 12 12 G 0 1 M 2 2 G 0 1 M 476 476 G 1 0 M 64 64 G 1 0 M 26 26 G 1 0 M 53 53 G 1 0 M 38 38 G 1 0 M 4 4 G 1 0 M 25 25 G 1 0 M 23 23 G 1 0 M 15 15',

        q_id     => 'BI831275.1',
        q_start  => 0,
        q_end    => 746,
        q_strand => '+',
        t_id     => 'OTTHUMT00000039637',
        t_start  => 57,
        t_end    => 797,
        t_strand => '+',
        score    => 3471,
        n_ele    => 21,

        ts_strand => -1,
        exons     => [
            [ 136243, 137923 ], # OTTHUME00000175054 1681bp
            [ 139767, 139934 ], # OTTHUME00000175059  168bp
            [ 140019, 140161 ], # OTTHUME00000175058  143bp
            [ 141793, 141910 ], # OTTHUME00000175064  118bp
            [ 142460, 142597 ], # OTTHUME00000175057  138bp
            [ 144330, 144505 ], # OTTHUME00000175063  176bp
            [ 145723, 145917 ], # OTTHUME00000175061  195bp -57 = 138
            ],
        clone_contig_offset => 100,    # contig starts at bp 100 in clone; ts is rel contig

        intron_vulgar  => 'M 12 12 G 0 1 M 2 2 G 0 1 M 122 122 I 0 1217 M 176 176 I 0 1732 M 138 138 I 0 549 M 40 40 G 1 0 M 64 64 G 1 0 M 14 14 I 0 1631 M 12 12 G 1 0 M 53 53 G 1 0 M 38 38 G 1 0 M 4 4 G 1 0 M 25 25 G 1 0 M 11 11 I 0 84 M 12 12 G 1 0 M 15 15',

        intron_t_start => 145960,
        intron_t_end   => 140007,
        intron_t_strand=> '-',
        intron_n_ele   => 31,

        splits => [
            'BI831275.1 0 136 + OTTHUMT00000039637 145960 145822 - 0 M 12 12 G 0 1 M 2 2 G 0 1 M 122 122',
            'BI831275.1 136 312 + OTTHUMT00000039637 144605 144429 - 0 M 176 176',
            'BI831275.1 312 450 + OTTHUMT00000039637 142697 142559 - 0 M 138 138',
            'BI831275.1 450 570 + OTTHUMT00000039637 142010 141892 - 0 M 40 40 G 1 0 M 64 64 G 1 0 M 14 14',
            'BI831275.1 570 718 + OTTHUMT00000039637 140261 140118 - 0 M 12 12 G 1 0 M 53 53 G 1 0 M 38 38 G 1 0 M 4 4 G 1 0 M 25 25 G 1 0 M 11 11',
            'BI831275.1 718 746 + OTTHUMT00000039637 140034 140007 - 0 M 12 12 G 1 0 M 15 15',
            ],
    },

    # Test clone cases start here

    {
        name     => 'Test fwd region vs BC018923.fwd (+)',
        vulgar   => 'BC018923.fwd 0 2538 + EMBOSS_001 0 2537 + 12625 ' . $test_clone_exp{ts_vulgar_comps_fwd},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.fwd',
        q_start  => 0,
        q_end    => 2538,
        q_strand => '+',

        t_start  => 0,
        t_end    => 2537,
        t_strand => '+',

        ts_strand => 1,
        exons     => $test_clone_exp{exons_fwd_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_fwd},
        intron_t_start => $test_clone_exp{fwd_region_v_min},
        intron_t_end   => $test_clone_exp{fwd_region_max},
        intron_t_strand=> '+',

        split_components => [
            'BC018923.fwd', $test_clone_exp{v_fwd_query_exons_fwd}, '+', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_fwd_region},    '+', # target
            0,              $test_clone_exp{exon_vulgars_fwd},           # score, vulgar string
        ],

        # BS: BC018923.fwd 0 974 + EMBOSS_001 120388 121362 + 0 M 974 974
        # BS: BC018923.fwd 974 1166 + EMBOSS_001 123608 123801 + 0 M 33 33 G 0 1 M 159 159
        # BS: BC018923.fwd 1166 1333 + EMBOSS_001 125113 125278 + 0 M 55 55 G 2 0 M 110 110
        # BS: BC018923.fwd 1333 1563 + EMBOSS_001 134179 134409 + 0 M 230 230
        # BS: BC018923.fwd 1563 1719 + EMBOSS_001 138322 138478 + 0 M 156 156
        # BS: BC018923.fwd 1719 1799 + EMBOSS_001 139240 139320 + 0 M 80 80
        # BS: BC018923.fwd 1799 2538 + EMBOSS_001 139923 140662 + 0 M 739 739
    },
    {
        name     => 'Test rev region vs BC018923.rev (+)',
        vulgar   => 'BC018923.rev 15 2553 + EMBOSS_001 2537 0 - 12625 ' . $test_clone_exp{ts_vulgar_comps_rev},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.rev',
        q_start  => 15,
        q_end    => 2553,
        q_strand => '+',

        t_start  => 2537,
        t_end    => 0,
        t_strand => '-',

        ts_strand => -1,
        exons     => $test_clone_exp{exons_rev_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_rev},
        intron_t_start => $test_clone_exp{rev_region_v_min},
        intron_t_end   => $test_clone_exp{rev_region_max},
        intron_t_strand=> '+',

        split_components => [
            'BC018923.rev', $test_clone_exp{v_rev_query_exons_fwd}, '+', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_rev_region},    '+', # target
            0,              $test_clone_exp{exon_vulgars_rev},           # score, vulgar string
            ],

        # BS: BC018923.rev 15 754 + EMBOSS_001 35000 35739 + 0 M 739 739
        # BS: BC018923.rev 754 834 + EMBOSS_001 36342 36422 + 0 M 80 80
        # BS: BC018923.rev 834 990 + EMBOSS_001 37184 37340 + 0 M 156 156
        # BS: BC018923.rev 990 1220 + EMBOSS_001 41253 41483 + 0 M 230 230
        # BS: BC018923.rev 1220 1387 + EMBOSS_001 50384 50549 + 0 M 110 110 G 2 0 M 55 55
        # BS: BC018923.rev 1387 1579 + EMBOSS_001 51861 52054 + 0 M 159 159 G 0 1 M 33 33
        # BS: BC018923.rev 1579 2553 + EMBOSS_001 54300 55274 + 0 M 974 974
    },
    {
        name     => 'Test fwd region vs BC018923.rev (+)',
        vulgar   => 'BC018923.rev 15 2553 + EMBOSS_001 2537 0 - 12625 ' . $test_clone_exp{ts_vulgar_comps_rev},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.rev',
        q_start  => 15,
        q_end    => 2553,
        q_strand => '+',

        t_start  => 2537,
        t_end    => 0,
        t_strand => '-',

        ts_strand => 1,
        exons     => $test_clone_exp{exons_fwd_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_rev},
        intron_t_start => $test_clone_exp{fwd_region_max},
        intron_t_end   => $test_clone_exp{fwd_region_v_min},
        intron_t_strand=> '-',

        split_components => [
            'BC018923.rev', $test_clone_exp{v_rev_query_exons_fwd},   '+', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_fwd_region_revd}, '-', # target
            0,              $test_clone_exp{exon_vulgars_rev},             # score, vulgar string
            ],

        # BS: BC018923.rev 15 754 + EMBOSS_001 140662 139923 - 0 M 739 739
        # BS: BC018923.rev 754 834 + EMBOSS_001 139320 139240 - 0 M 80 80
        # BS: BC018923.rev 834 990 + EMBOSS_001 138478 138322 - 0 M 156 156
        # BS: BC018923.rev 990 1220 + EMBOSS_001 134409 134179 - 0 M 230 230
        # BS: BC018923.rev 1220 1387 + EMBOSS_001 125278 125113 - 0 M 110 110 G 2 0 M 55 55
        # BS: BC018923.rev 1387 1579 + EMBOSS_001 123801 123608 - 0 M 159 159 G 0 1 M 33 33
        # BS: BC018923.rev 1579 2553 + EMBOSS_001 121362 120388 - 0 M 974 974
    },
    {
        name     => 'Test rev region vs BC018923.fwd (+)',
        vulgar   => 'BC018923.fwd 0 2538 + EMBOSS_001 0 2537 + 12625 ' . $test_clone_exp{ts_vulgar_comps_fwd},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.fwd',
        q_start  => 0,
        q_end    => 2538,
        q_strand => '+',

        t_start  => 0,
        t_end    => 2537,
        t_strand => '+',

        ts_strand => -1,
        exons     => $test_clone_exp{exons_rev_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_fwd},
        intron_t_start => $test_clone_exp{rev_region_max},
        intron_t_end   => $test_clone_exp{rev_region_v_min},
        intron_t_strand=> '-',

        split_components => [
            'BC018923.fwd', $test_clone_exp{v_fwd_query_exons_fwd},   '+', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_rev_region_revd}, '-', # target
            0,              $test_clone_exp{exon_vulgars_fwd},             # score, vulgar string
            ],

        # BS: BC018923.fwd 0 974 + EMBOSS_001 55274 54300 - 0 M 974 974
        # BS: BC018923.fwd 974 1166 + EMBOSS_001 52054 51861 - 0 M 33 33 G 0 1 M 159 159
        # BS: BC018923.fwd 1166 1333 + EMBOSS_001 50549 50384 - 0 M 55 55 G 2 0 M 110 110
        # BS: BC018923.fwd 1333 1563 + EMBOSS_001 41483 41253 - 0 M 230 230
        # BS: BC018923.fwd 1563 1719 + EMBOSS_001 37340 37184 - 0 M 156 156
        # BS: BC018923.fwd 1719 1799 + EMBOSS_001 36422 36342 - 0 M 80 80
        # BS: BC018923.fwd 1799 2538 + EMBOSS_001 35739 35000 - 0 M 739 739
    },
    {
        name     => 'Test fwd region vs BC018923.fwd (-)',
        vulgar   => 'BC018923.fwd 2538 0 - EMBOSS_001 2537 0 - 12625 ' . $test_clone_exp{ts_vulgar_comps_rev},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.fwd',
        q_start  => 2538,
        q_end    => 0,
        q_strand => '-',

        t_start  => 2537,
        t_end    => 0,
        t_strand => '-',

        ts_strand => 1,
        exons     => $test_clone_exp{exons_fwd_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_rev},
        intron_t_start => $test_clone_exp{fwd_region_max},
        intron_t_end   => $test_clone_exp{fwd_region_v_min},
        intron_t_strand=> '-',

        # We expect these to be the same as Test fwd region vs BC018923.rev (+) on target side,
        # but query side exons will be for BC018923.fwd

        split_components => [
            'BC018923.fwd', $test_clone_exp{v_fwd_query_exons_rev},   '-', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_fwd_region_revd}, '-', # target
            0,              $test_clone_exp{exon_vulgars_rev},             # score, vulgar string
            ],

        # BS: BC018923.fwd 2538 1799 - EMBOSS_001 140662 139923 - 0 M 739 739
        # BS: BC018923.fwd 1799 1719 - EMBOSS_001 139320 139240 - 0 M 80 80
        # BS: BC018923.fwd 1719 1563 - EMBOSS_001 138478 138322 - 0 M 156 156
        # BS: BC018923.fwd 1563 1333 - EMBOSS_001 134409 134179 - 0 M 230 230
        # BS: BC018923.fwd 1333 1166 - EMBOSS_001 125278 125113 - 0 M 110 110 G 2 0 M 55 55
        # BS: BC018923.fwd 1166 974 - EMBOSS_001 123801 123608 - 0 M 159 159 G 0 1 M 33 33
        # BS: BC018923.fwd 974 0 - EMBOSS_001 121362 120388 - 0 M 974 974
    },
    {
        name     => 'Test rev region vs BC018923.rev (-)',
        vulgar   => 'BC018923.rev 2553 15 - EMBOSS_001 0 2537 + 12625 ' . $test_clone_exp{ts_vulgar_comps_fwd},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.rev',
        q_start  => 2553,
        q_end    => 15,
        q_strand => '-',

        t_start  => 0,
        t_end    => 2537,
        t_strand => '+',

        ts_strand => -1,
        exons     => $test_clone_exp{exons_rev_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_fwd},
        intron_t_start => $test_clone_exp{rev_region_max},
        intron_t_end   => $test_clone_exp{rev_region_v_min},
        intron_t_strand=> '-',

        # We expect these to be the same as Test rev region vs BC018923.fwd (+) on target side,
        # but query side exons will be for BC018923.rev

        split_components => [
            'BC018923.rev', $test_clone_exp{v_rev_query_exons_rev},   '-', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_rev_region_revd}, '-', # target
            0,              $test_clone_exp{exon_vulgars_fwd},             # score, vulgar string
            ],

        # BS: BC018923.rev 2553 1579 - EMBOSS_001 55274 54300 - 0 M 974 974
        # BS: BC018923.rev 1579 1387 - EMBOSS_001 52054 51861 - 0 M 33 33 G 0 1 M 159 159
        # BS: BC018923.rev 1387 1220 - EMBOSS_001 50549 50384 - 0 M 55 55 G 2 0 M 110 110
        # BS: BC018923.rev 1220 990 - EMBOSS_001 41483 41253 - 0 M 230 230
        # BS: BC018923.rev 990 834 - EMBOSS_001 37340 37184 - 0 M 156 156
        # BS: BC018923.rev 834 754 - EMBOSS_001 36422 36342 - 0 M 80 80
        # BS: BC018923.rev 754 15 - EMBOSS_001 35739 35000 - 0 M 739 739
    },
    {
        name     => 'Test fwd region vs BC018923.rev (-)',
        vulgar   => 'BC018923.rev 2553 15 - EMBOSS_001 0 2537 + 12625 ' . $test_clone_exp{ts_vulgar_comps_fwd},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.rev',
        q_start  => 2553,
        q_end    => 15,
        q_strand => '-',

        t_start  => 0,
        t_end    => 2537,
        t_strand => '+',

        ts_strand => 1,
        exons     => $test_clone_exp{exons_fwd_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_fwd},
        intron_t_start => $test_clone_exp{fwd_region_v_min},
        intron_t_end   => $test_clone_exp{fwd_region_max},
        intron_t_strand=> '+',

        split_components => [
            'BC018923.rev', $test_clone_exp{v_rev_query_exons_rev},   '-', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_fwd_region},      '+', # target
            0,              $test_clone_exp{exon_vulgars_fwd},             # score, vulgar string
            ],

        # BS: BC018923.rev 2553 1579 - EMBOSS_001 120388 121362 + 0 M 974 974
        # BS: BC018923.rev 1579 1387 - EMBOSS_001 123608 123801 + 0 M 33 33 G 0 1 M 159 159
        # BS: BC018923.rev 1387 1220 - EMBOSS_001 125113 125278 + 0 M 55 55 G 2 0 M 110 110
        # BS: BC018923.rev 1220 990 - EMBOSS_001 134179 134409 + 0 M 230 230
        # BS: BC018923.rev 990 834 - EMBOSS_001 138322 138478 + 0 M 156 156
        # BS: BC018923.rev 834 754 - EMBOSS_001 139240 139320 + 0 M 80 80
        # BS: BC018923.rev 754 15 - EMBOSS_001 139923 140662 + 0 M 739 739
    },
   {
        name     => 'Test rev region vs BC018923.fwd (-)',
        vulgar   => 'BC018923.fwd 2538 0 - EMBOSS_001 2537 0 - 12625 ' . $test_clone_exp{ts_vulgar_comps_rev},

        %{$test_clone_exp{invariants}},

        q_id     => 'BC018923.fwd',
        q_start  => 2538,
        q_end    => 0,
        q_strand => '-',

        t_start  => 2537,
        t_end    => 0,
        t_strand => '-',

        ts_strand => -1,
        exons     => $test_clone_exp{exons_rev_region},

        intron_vulgar  => $test_clone_exp{intronified_vulgar_comps_rev},
        intron_t_start => $test_clone_exp{rev_region_v_min},
        intron_t_end   => $test_clone_exp{rev_region_max},
        intron_t_strand=> '+',

        split_components => [
            'BC018923.fwd', $test_clone_exp{v_fwd_query_exons_rev},   '-', # query
            'EMBOSS_001',   $test_clone_exp{v_exons_rev_region},      '+', # target
            0,              $test_clone_exp{exon_vulgars_rev},             # score, vulgar string
            ],

        # BS: BC018923.fwd 2538 1799 - EMBOSS_001 35000 35739 + 0 M 739 739
        # BS: BC018923.fwd 1799 1719 - EMBOSS_001 36342 36422 + 0 M 80 80
        # BS: BC018923.fwd 1719 1563 - EMBOSS_001 37184 37340 + 0 M 156 156
        # BS: BC018923.fwd 1563 1333 - EMBOSS_001 41253 41483 + 0 M 230 230
        # BS: BC018923.fwd 1333 1166 - EMBOSS_001 50384 50549 + 0 M 110 110 G 2 0 M 55 55
        # BS: BC018923.fwd 1166 974 - EMBOSS_001 51861 52054 + 0 M 159 159 G 0 1 M 33 33
        # BS: BC018923.fwd 974 0 - EMBOSS_001 54300 55274 + 0 M 974 974
    },
    );

# Coverage matrix: . = tiny, * = real or test
#
#          | q / t strands
# ---------+-----+-----+-----+-----
# ts_strand| +/+ | +/- | -/+ | -/-
# ---------+-----+-----+-----+-----
#        + | .** | *   | *   | *
# ---------+-----+-----+-----+-----
#        - | .** | *   | *   | *
# ---------+-----+-----+-----+-----


foreach my $test (@split_expected) {
    note("Split tests for '", $test->{name}, "'");

    my $ga = $ga_module->from_vulgar($test->{vulgar});
    isa_ok($ga, 'Bio::Otter::GappedAlignment');

    is($ga->query_id,      $test->{q_id},     'query_id');
    is($ga->query_start,   $test->{q_start},  'query_start');
    is($ga->query_end,     $test->{q_end},    'query_end');
    is($ga->query_strand,  $test->{q_strand}, 'query_strand');
    is($ga->target_id,     $test->{t_id},     'target_id');
    is($ga->target_start,  $test->{t_start},  'target_start');
    is($ga->target_end,    $test->{t_end},    'target_end');
    is($ga->target_strand, $test->{t_strand}, 'target_strand');
    is($ga->score,         $test->{score},    'score');
    is($ga->n_elements,    $test->{n_ele},    'n_elements');
    is($ga->vulgar_string, $test->{vulgar},   'vulgar_string');

    my $ts = Hum::Ace::SubSeq->new();
    $ts->strand($test->{ts_strand});
    my $offset = $test->{clone_contig_offset} || 0;
    foreach my $exon (@{$test->{exons}}) {
        my $e = Hum::Ace::Exon->new();
        $e->start($exon->[0] + $offset);
        $e->end(  $exon->[1] + $offset);
        $ts->add_Exon($e);
    }

    my $intron_ga = $ga->intronify_by_transcript_exons($ts);
    isa_ok($intron_ga, 'Bio::Otter::GappedAlignment');
    note("Intronified vulgar: ", $intron_ga->vulgar_string);
    is ($intron_ga->vulgar_comps_string, $test->{intron_vulgar}, 'intronify');
    is($intron_ga->query_id,      $test->{q_id},     'query_id');
    is($intron_ga->query_start,   $test->{q_start},  'query_start');
    is($intron_ga->query_end,     $test->{q_end},    'query_end');
    is($intron_ga->query_strand,  $test->{q_strand}, 'query_strand');
    is($intron_ga->target_id,     $test->{t_id},     'target_id');
    is($intron_ga->target_start,  $test->{intron_t_start}, 'target_start');
    is($intron_ga->target_end,    $test->{intron_t_end},   'target_end');
    is($intron_ga->target_strand, $test->{intron_t_strand},'target_strand');
    is($intron_ga->score,         $test->{score},          'score');
    is($intron_ga->n_elements,    $test->{intron_n_ele},   'n_elements');

    my @split = $ga->split_by_transcript_exons($ts);
    my $n_splits = scalar(@split);

    my @e_splits;
    if ($test->{split_components}) {
        @e_splits = build_splits($test->{split_components});
    } else {
        @e_splits = @{$test->{splits}};
    }
    is($n_splits, scalar(@e_splits), 'n_splits');

    unless ($test->{skip_split_tests}) {
        foreach my $n ( 0 .. ($n_splits - 1) ) {
            isa_ok($split[$n], 'Bio::Otter::GappedAlignment');
            is ($split[$n]->vulgar_string, $e_splits[$n], "split $n");
        }
    }
}

done_testing;

sub adjust_start_coords {
    my ($coords, $offset) = @_;
    return [ map { [ $_->[0] + $offset, $_->[1] ] } @$coords ];
}

# Components are either scalars which are identical for each split,
# or arrayrefs where one item should be taken in order for each split.
#
sub build_splits {
    my $components = shift;

    # Get number of splits and check for consistency
    my $n;
    map {
        if (reftype($_) and reftype($_) eq 'ARRAY') {
            my $this_n = scalar(@$_);
            if ($n) {
                die "Split component sizes do not match, prev $n, this $this_n." unless $n == $this_n;
            } else {
                $n = scalar(@$_);
            }
        }
    } @$components;

    my @splits;
    foreach my $i ( 0..($n-1) ) {
        push @splits, join ' ', map {
            (reftype($_) and reftype($_) eq 'ARRAY') ? flatten(' ', $_->[$i]) : $_;
        } @$components;
        note('BS: ', $splits[$i]);
    }

    return @splits;
}

sub flatten {
    # Some per-split components are start/end arrays themselves, and need to be flattened
    my ($glue, $item) = @_;
    my $result = (reftype($item) and reftype($item) eq 'ARRAY') ? join($glue, @$item) : $item;
    return $result;
}

sub reverse_exon_coords {
    my $coords = shift;
    return [ reverse map { [ reverse @$_ ] } @$coords ];
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
