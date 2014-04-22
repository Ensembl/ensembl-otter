#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my ($getscript_module, $localdb_module);
BEGIN {
    $getscript_module = 'Bio::Otter::Utils::GetScript';
    use_ok($getscript_module);
    $localdb_module = 'Bio::Otter::Utils::GetScript::LocalDB';
    use_ok($localdb_module);
}

critic_module_ok($getscript_module);
critic_module_ok($localdb_module);

{
    my $gs = new_ok($getscript_module);
    # ensure $gs goes out of scope
}

{
    my $ld = new_ok($localdb_module);
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
