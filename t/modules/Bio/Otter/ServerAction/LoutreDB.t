#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;
use Test::Otter qw( ^db_or_skipall );

use Bio::Otter::Server::Support::Local;

my ($saldb_module, $saldb_tsv_module);

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

my $db_info = $ldb_plain->get_db_info;
ok($db_info, 'get_db_info');
note('Got ', scalar keys %$db_info, ' entries');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
