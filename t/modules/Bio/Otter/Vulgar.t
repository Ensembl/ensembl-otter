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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Vulgar';
    use_ok($module);
}
critic_module_ok($module);

my $v_string = 'Query 0 20 + Target 21 6 - 56 M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0';
my $exp = {
    q_id     => 'Query',
    q_start  => 0,
    q_end    => 20,
    q_strand => '+',
    q_sense  => 1,
    q_ensembl => [1, 20, 1],
    t_id     => 'Target',
    t_start  => 21,
    t_end    => 6,
    t_strand => '-',
    t_sense  => -1,
    t_ensembl => [7, 21, -1],
    score    => 56,
    n_ele    => 6,
    string   => $v_string,
};

my $v1 = new_ok($module => [ $v_string ]);
vulgar_ok($v1, 'from one arg', $exp);

my $v2 = new_ok($module => [ vulgar_string => $v_string ]);
vulgar_ok($v2, 'from vulgar_string opt', $exp);

my @comps;
my $ok = $v2->parse_align_comps(
    sub {
        my ($t, $q_len, $t_len) = @_;
        push @comps, [$t, $q_len, $t_len];
        return 1;
    }
    );
ok($ok, 'parse_align_comps');
is(scalar(@comps), $exp->{n_ele}, 'n_comps');
vulgar_ok($v2, 'v2 unchanged', $exp);

my $v3 = $v1->copy;
isa_ok($v3, $module, 'copy');
isnt($v3, $v1, 'copy is new object');
isnt($v3->{_align_comps}, $v1->{_align_comps}, 'copy _align_comps are new arrayref');
vulgar_ok($v3, 'copy', $exp);

my $v4 = new_ok($module => [ vulgar_comps_string => 'M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0' ]);
note("v4 string is: '", $v4->string, "'");
$v4->query_id('Query');
$v4->query_start(0);
$v4->query_end(20);
$v4->query_strand('+');
$v4->target_id('Target');
$v4->target_start(21);
$v4->target_end(6);
$v4->target_strand(-1);
$v4->score(56);
vulgar_ok($v4, 'from vulgar_comps_string', $exp);

my $v5 = new_ok($module => [ vulgar_comps_string => 'M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0' ]);
note("v5 string is: '", $v5->string, "'");
$v5->query_id('Query');
$v5->set_query_from_ensembl(1, 20, 1);
$v5->target_id('Target');
$v5->set_target_from_ensembl(7, 21, -1);
$v5->score(56);
vulgar_ok($v5, 'from vulgar_comps_string', $exp);

done_testing;

sub vulgar_ok {
    my ($vulgar, $desc, $expect) = @_;
    subtest $desc => sub {
        is($vulgar->query_id,      $expect->{q_id},     'query_id');
        is($vulgar->query_start,   $expect->{q_start},  'query_start');
        is($vulgar->query_end,     $expect->{q_end},    'query_end');
        is($vulgar->query_strand,  $expect->{q_strand}, 'query_strand');
        is($vulgar->query_strand_sense,  $expect->{q_sense}, 'query_strand_sense');
        is_deeply([ $vulgar->query_ensembl_coords ], $expect->{q_ensembl}, 'query_ensembl_coords');
        is($vulgar->target_id,     $expect->{t_id},     'target_id');
        is($vulgar->target_start,  $expect->{t_start},  'target_start');
        is($vulgar->target_end,    $expect->{t_end},    'target_end');
        is($vulgar->target_strand, $expect->{t_strand}, 'target_strand');
        is($vulgar->target_strand_sense, $expect->{t_sense}, 'target_strand_sense');
        is_deeply([ $vulgar->target_ensembl_coords ], $expect->{t_ensembl}, 'target_ensembl_coords');
        is($vulgar->score,         $expect->{score},    'score');
        is($vulgar->n_elements,    $expect->{n_ele},    'n_elements');
        is($vulgar->string,        $expect->{string},   'string');
        done_testing;
    };
    return;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
