#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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
use Test::Otter qw( ^data_dir_or_skipall ^db_or_skipall );

use Bio::Otter::Server::Config;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::StableId';
    use_ok($module);
}
critic_module_ok($module);

my $dataset = Bio::Otter::Server::Config->SpeciesDat->dataset('human');

my $sid = new_ok($module => [ $dataset->otter_dba ]);

is($sid->primary_prefix, 'OTT', 'primary prefix for human');
is($sid->species_prefix, 'HUM', 'species prefix for human');

ott_tests("with dataset", $sid);

is($sid->type_for_id('OTTMUST00000010323'), undef, 'OTTMUST... is undef');
is($sid->type_for_id('ENSHUMG00000012345'), undef, 'ENSHUMG... is undef');

my $sid_no_ds = new_ok($module);

ott_tests("no dataset", $sid_no_ds);

is($sid_no_ds->type_for_id('OTTMUST00000010323'), 'Transcript', 'OTTMUST... is transcript');
is($sid_no_ds->type_for_id('ENSHUMG00000012345'), 'Gene',       'ENSHUMG... is gene');

done_testing;

sub ott_tests {
    my ($name, $stabid) = @_;
    subtest "OTT: $name" => sub {
        is($stabid->type_for_id('OTTHUMT00000010323'), 'Transcript',  'OTTHUMT... is transcript');
        is($stabid->type_for_id('OTTHUMG00000003645'), 'Gene',        'OTTHUMG... is gene');
        is($stabid->type_for_id('OTTHUMP00000000234'), 'Translation', 'OTTHUMP... is translation');
        is($stabid->type_for_id('OTTHUME00000000012'), 'Exon',        'OTTHUME... is exon');
        is($stabid->type_for_id('OTTHUMA00000000012'), undef,         'OTTHUMA... is undef');
    };
    return;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
