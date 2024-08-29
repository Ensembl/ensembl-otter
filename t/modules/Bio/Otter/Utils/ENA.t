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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::ENA';
    use_ok($module);
}

critic_module_ok($module);

my $ena = $module->new;
isa_ok($ena, $module);

my @valid_accs = qw(ERS000123 SRS000012 DRS000234);
my @invalid_accs = qw(ERA000012 XYZ123456 AA020997); # one submission, one nonsense, one non-SRA

my $results = $ena->get_sample_accessions(@valid_accs, @invalid_accs);
is(ref($results), 'HASH', 'results hash');

foreach my $valid ( @valid_accs ) {
    my $sample = $results->{$valid};
    ok($sample, "$valid: have result");
}

foreach my $invalid ( @invalid_accs ) {
    my $sample = $results->{$invalid};
    ok(not($sample), "$invalid: no result");
}

my $at_results = $ena->get_sample_accession_types(@valid_accs, @invalid_accs);
is(ref($at_results), 'HASH', 'at_results hash');

foreach my $valid ( @valid_accs ) {
    my $at = $at_results->{$valid};
    ok($at, "$valid: have at_result");
    ok($at->{taxon_list}, "$valid: has taxon_list");
    note("\ttaxon_id:\t", $at->{taxon_list});
    note("\ttitle:\t\t", $at->{description});
}

foreach my $invalid ( @invalid_accs ) {
    my $at = $at_results->{$invalid};
    ok(not($at), "$invalid: no at_result");
}

# Singleton
my $acc = $valid_accs[1];
my $s_results = $ena->get_sample_accessions($acc);
is(ref($s_results), 'HASH', 's_results hash');
ok($s_results->{$acc}, 'result is for singleton acc');

# Empty
my $e_results = $ena->get_sample_accessions();
is(ref($e_results), 'HASH', 'e_results hash');
ok(not(%$e_results), 'result is empty');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
