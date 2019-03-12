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
use Test::Otter qw( ^db_or_skipall );

use Bio::Otter::Server::Support::Local;

my ($saldb_module);

BEGIN {
    $saldb_module = qw( Bio::Otter::ServerAction::LoutreDB );
    use_ok($saldb_module);
}

critic_module_ok($saldb_module);

my $server = Bio::Otter::Server::Support::Local->new;
$server->set_params( dataset => 'human_test' );

my $ldb_plain = new_ok($saldb_module => [ $server ]);

my $meta = $ldb_plain->get_meta;
ok($meta, 'get_meta');
note('Got ', scalar keys %$meta, ' keys');

$server->set_params( key => 'species.' );
my $s_meta = $ldb_plain->get_meta;
ok($s_meta, 'get_meta(species.)');
note('Got ', scalar keys %$s_meta, ' keys');

$server->set_params( key => 'species.taxonomy_id' );
$s_meta = $ldb_plain->get_meta;
ok($s_meta, 'get_meta(species.taxonomy_id)');
is(scalar keys %$s_meta, 1, 'only one key when exact spec');

my $db_info = $ldb_plain->get_db_info;
ok($db_info, 'get_db_info');
note('Got ', scalar keys %$db_info, ' entries');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
