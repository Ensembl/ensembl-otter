#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my ($getscript_module, $localdb_module);
BEGIN {
    $getscript_module = 'Bio::Otter::Utils::GetScript';
    use_ok($getscript_module);
    $localdb_module = 'Bio::Otter::Utils::GetScript::LocalDB';
    use_ok($localdb_module);
}

critic_module_ok($getscript_module);
critic_module_ok($localdb_module);

{
    my $gs = new_ok($getscript_module);
    # ensure $gs goes out of scope
}

{
    my $ld = new_ok($localdb_module);
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
