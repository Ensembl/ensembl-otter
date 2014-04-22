#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $saf_module;
BEGIN {
    $saf_module = 'Bio::Vega::SplicedAlignFeature';
    use_ok($saf_module);
}
critic_module_ok($saf_module);

throws_ok(sub { $saf_module->new },
          qr/One of CIGAR_STRING, VULGAR.* or FEATURES/,
          'throws if no args');

throws_ok(sub { $saf_module->new( '-cigar_string' => '4M', '-vulgar_string' => 'rude' ) },
          qr/Only one of CIGAR_STRING, VULGAR.* and FEATURES/,
          'throws if conflicting args');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
