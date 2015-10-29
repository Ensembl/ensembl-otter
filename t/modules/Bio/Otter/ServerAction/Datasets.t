#!/usr/bin/env perl

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
