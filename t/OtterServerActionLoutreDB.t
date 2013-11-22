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
    $saldb_tsv_module = qw( Bio::Otter::ServerAction::TSV::LoutreDB );
    use_ok($saldb_module);
    use_ok($saldb_tsv_module);
}

critic_module_ok($saldb_module);
critic_module_ok($saldb_tsv_module);

my $server = Bio::Otter::Server::Support::Local->new;
$server->set_params( dataset => 'human_test' );

my $ldb_plain = new_ok($saldb_module => [ $server ]);

my $meta = $ldb_plain->get_meta;
ok($meta, 'get_meta');
note('Got ', scalar @$meta, ' entries');

my $db_info = $ldb_plain->get_db_info;
ok($db_info, 'get_db_info');
note('Got ', scalar keys %$db_info, ' entries');

my $ldb_tsv = new_ok($saldb_tsv_module => [ $server ]);
my $meta_tsv = $ldb_tsv->get_meta;
ok($meta_tsv, 'get_meta - TSV');
note("Got:\n", $meta_tsv);

my $db_info_tsv = $ldb_tsv->get_db_info;
ok($db_info_tsv, 'get_db_info - TSV');
note("Got:\n", $db_info_tsv);

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
