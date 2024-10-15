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
use Test::Otter qw( ^db_or_skipall );

use Bio::Otter::Server::Support::Local;

my ($salds_module);

BEGIN {
    $salds_module = qw( Bio::Otter::ServerAction::Datasets );
    use_ok($salds_module);
}

critic_module_ok($salds_module);

my $server = Bio::Otter::Server::Support::Local->new;
$server->set_params( dataset => 'human_test' );

my $ldb_plain = new_ok($salds_module => [ $server ]);

my $ds = $ldb_plain->get_datasets;
ok($ds, 'get_datasets');
note('Got ', scalar keys %$ds, ' keys');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
