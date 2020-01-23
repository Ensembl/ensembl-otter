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
use Test::Otter qw( ^data_dir_or_skipall ^db_or_skipall );
use Test::Requires qw( Bio::EnsEMBL::Variation::DBSQL::DBAdaptor );

use Try::Tiny;

use Bio::Otter::Server::Config;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::EnsEMBL';
    use_ok($module);
}
critic_module_ok($module);

my $dataset = Bio::Otter::Server::Config->SpeciesDat->dataset('human');

my $ens = new_ok($module => [ $dataset ]);

my $ens_id = $ens->stable_ids_from_otter_id('OTTHUMT00000010323');
is($ens_id, 'ENST00000373833', 'EnsEMBL transcript id from Otter transcript id');

$ens_id = $ens->stable_ids_from_otter_id('OTTHUMG00000012711');
is($ens_id, 'ENSG00000254875', 'EnsEMBL gene id from Otter gene id');

$ens_id = $ens->stable_ids_from_otter_id('OTTHUMP00000018803');
is($ens_id, 'ENSP00000369497', 'EnsEMBL translation id from Otter translation id');

my ($okay, $error);
try {
    $ens_id = $ens->stable_ids_from_otter_id('OTTHUME00000230228');
    $okay = 1;
} catch {
    $error = $_;
};
ok(not($okay), 'attempt to lookup exon id dies as expected');
like($error, qr/not supported for exons/, 'error message ok');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
