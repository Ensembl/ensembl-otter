#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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
