#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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

my ($sa_ai_module, $sa_ai_apache_module);

BEGIN {
    $sa_ai_module = qw( Bio::Otter::ServerAction::AccessionInfo );
    $sa_ai_apache_module = qw( Bio::Otter::ServerAction::Apache::AccessionInfo );
    use_ok($sa_ai_module);
    use_ok($sa_ai_apache_module);
}

critic_module_ok($sa_ai_module);
critic_module_ok($sa_ai_apache_module);

my $server = Bio::Otter::Server::Support::Local->new;

my $ai_plain = new_ok($sa_ai_module => [ $server ]);
my $ai_apache = new_ok($sa_ai_apache_module => [ $server ]);

my @accessions = qw( AK125401.1 Q14031.3 ERS000123 xyzzy );
$server->set_params( accessions => \@accessions );
my $results = $ai_plain->get_accession_types;
ok($results, 'get_accession_types');
is(scalar keys %$results, 3, 'n(results)');

$server->set_params( accessions => join(',', @accessions) );
$results = $ai_apache->get_accession_types;
ok($results, 'get_accession_types - Apache');
is(scalar keys %$results, 3, 'n(results)');

my @taxon_ids = ( 9606, 10090, 90988, 12345678 );
$server->set_params( id => \@taxon_ids );
$results = $ai_plain->get_taxonomy_info;
ok($results, 'get_taxonomy_info');
is(scalar @$results, 3, 'n(results)');

$server->set_params( id => join(',', @taxon_ids) );
$results = $ai_apache->get_taxonomy_info;
ok($results, 'get_taxonomy_info - Apache');
is(scalar @$results, 3, 'n(results)');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
