#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $getscript_module;
BEGIN {
    $getscript_module = 'Bio::Otter::Utils::GetScript';
    use_ok($getscript_module);
}

critic_module_ok($getscript_module);

my $gs = new_ok($getscript_module);

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
