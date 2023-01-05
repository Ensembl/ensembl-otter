#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Attribute;
use Bio::Vega::Gene;
use Bio::Vega::Transcript;

my $vua_module;
BEGIN {
    $vua_module = 'Bio::Vega::Utils::AttributesMixin';
    use_ok($vua_module);
}
critic_module_ok($vua_module);

my $winterson = 'Oranges are not the only fruit';
my $non_bool_a = Bio::EnsEMBL::Attribute->new(-code => 'fruit',  -value => 'Apple');
my $non_bool_b = Bio::EnsEMBL::Attribute->new(-code => 'fruit',  -value => 'Banana');
my $non_bool_c = Bio::EnsEMBL::Attribute->new(-code => 'remark', -value => $winterson);
my $bool_false = Bio::EnsEMBL::Attribute->new(-code => 'cds_start_NF', -value => 0);
my $bool_true  = Bio::EnsEMBL::Attribute->new(-code => 'cds_start_NF', -value => 1);

my $ts1 = Bio::Vega::Transcript->new;
$ts1->add_Attributes($non_bool_a, $bool_false, $non_bool_c);
my $ts1_attrs = $ts1->Bio::Vega::Utils::AttributesMixin::all_Attributes_string();
is($ts1_attrs, "fruit=Apple-remark=$winterson", 'Transcript, false bool attr');

my $ts2 = Bio::Vega::Transcript->new;
$ts2->add_Attributes($non_bool_b, $non_bool_c, $bool_true);
my $ts2_attrs = $ts2->Bio::Vega::Utils::AttributesMixin::all_Attributes_string();
is($ts2_attrs, "cds_start_NF=1-fruit=Banana-remark=$winterson", 'Transcript, true bool attr');

my $g = Bio::Vega::Gene->new;
$g->add_Attributes($non_bool_a, $non_bool_c);
my $g_attrs = $g->Bio::Vega::Utils::AttributesMixin::all_Attributes_string();
is($g_attrs, "fruit=Apple-remark=$winterson", 'Gene');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
