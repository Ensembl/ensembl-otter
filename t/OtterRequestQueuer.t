#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::Otter;
use OtterTest::SessionWindow;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::RequestQueuer';
    use_ok($module);
}

critic_module_ok($module);

my $sw = OtterTest::SessionWindow->new;
my $rq = new_ok($module => [ $sw ]);

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
