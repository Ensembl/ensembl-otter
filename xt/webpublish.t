#!perl
use strict;
use warnings;

# Run with
#   prove -v -r xt
#
# Wallclock (CPU bound on one thread)
#    2m15s on a standard deskpro
#      40s on Mike's i5

use Test::Otter;
use Test::Perl::Critic -profile => Test::Otter->proj_rel('xt/webpublish.perlcriticrc');
all_critic_ok(map { Test::Otter->proj_rel($_) }
              qw( modules/Bio scripts/apache ));
