#!perl
use strict;
use warnings;

# Run with
#   prove -v -r xt
#
# Wallclock (CPU bound on one thread)
#    2m15s on a standard deskpro
#      40s on Mike's i5

use Test::Perl::Critic -profile => 'xt/webpublish.perlcriticrc';
all_critic_ok(qw( modules/Bio scripts/apache ));
