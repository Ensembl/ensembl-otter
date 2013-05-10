#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $saf_module;
BEGIN {
    $saf_module = 'Bio::Vega::SplicedAlignFeature';
    use_ok($saf_module);
}
critic_module_ok($saf_module);

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
