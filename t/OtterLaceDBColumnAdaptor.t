#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use Test::Otter qw( ^data_dir_or_skipall ); # also finds test libraries
use OtterTest::DB;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $adaptor_module;
BEGIN {
      $adaptor_module = 'Bio::Otter::Lace::DB::ColumnAdaptor';
      use_ok($adaptor_module);
}

critic_module_ok($adaptor_module);

my $test_db = OtterTest::DB->new;
my $ca = new_ok($adaptor_module => [ $test_db->dbh ]);

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
