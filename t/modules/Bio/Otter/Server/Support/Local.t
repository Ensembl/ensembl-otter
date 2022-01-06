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
use Test::SetupLog4perl;

use Test::More;

use Test::Otter qw( ^db_or_skipall ^data_dir_or_skipall ); # may skip test

use OtterTest::TestRegion;
use Bio::Otter::ServerAction::Region; # a specimen ServerAction.

my $module;

BEGIN {
    $module = 'Bio::Otter::Server::Support::Local';
    use_ok($module);
}

critic_module_ok($module);

my $local_server = new_ok($module);
my $params = OtterTest::TestRegion->new(0)->region_params;
ok($local_server->set_params(%$params), 'set_params');
is($local_server->param($_), $params->{$_}, "param '$_'") foreach keys %$params;

my $otter_dba = $local_server->otter_dba;
isa_ok($otter_dba, 'Bio::Vega::DBSQL::DBAdaptor');

my $sa_region = Bio::Otter::ServerAction::Region->new_with_slice($local_server);
isa_ok($sa_region, 'Bio::Otter::ServerAction::Region');

my $result = $sa_region->get_assembly_dna;
my $dna = $result->{dna};
ok($dna, 'get_assembly_dna');
note('Got ', length $dna, ' bp');

my $region = $sa_region->get_region;
isa_ok($region, 'Bio::Vega::Region');

my $local_server_2 = new_ok($module, [ otter_dba => $otter_dba ]);

my $otter_dba_2 = $local_server->otter_dba;
isa_ok($otter_dba_2, 'Bio::Vega::DBSQL::DBAdaptor');
is($otter_dba_2, $otter_dba, 'instantiate with otter_dba');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
