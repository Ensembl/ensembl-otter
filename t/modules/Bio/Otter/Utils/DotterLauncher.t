#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::DotterLauncher';
    use_ok($module);
}
critic_module_ok($module);
my $dl = new_ok($module);

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
