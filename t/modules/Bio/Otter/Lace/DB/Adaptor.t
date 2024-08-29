#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Test::More;

# FIXME: lots of boilerplate here.

use Test::Otter qw( ^data_dir_or_skipall ); # also finds test libraries
use OtterTest::DB;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $adaptor_module;
BEGIN {
      $adaptor_module = 'Bio::Otter::Lace::DB::Adaptor';
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
