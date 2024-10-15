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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Bio::Seq;

use Test::More tests => 11;

my $module;
BEGIN {
    $module = 'Bio::Vega::Utils::Evidence';
    use_ok($module, qw/get_accession_type reverse_seq/); 
}

critic_module_ok($module);

# Basics

my @r = get_accession_type('AA913908.1');
ok(scalar(@r), 'get versioned accession');

my ($type, $acc_sv, $src_db, $seq_len, $taxon_list, $desc) = @r;
is ($type, 'EST', 'type (versioned accession)');
is ($acc_sv, 'AA913908.1', 'acc_sv (versioned_accession)');

@r = get_accession_type('AA913908');
ok(scalar(@r), 'get unversioned accession');

($type, $acc_sv, $src_db, $seq_len, $taxon_list, $desc) = @r;
is ($type, 'EST', 'type (unversioned accession)');
is ($acc_sv, 'AA913908.1', 'acc_sv (unversioned accession)');

my $f_seq = Bio::Seq->new(
    -seq   => 'GATTACCA',
    -id    => 'test',
    );
my $r_seq = reverse_seq( $f_seq );
ok($r_seq, 'reverse_seq did something');
is($r_seq->seq, 'TGGTAATC', 'seq');
is($r_seq->display_id, 'test.rev', 'display_id');

1;

# Local Variables:
# mode: perl
# End:

# EOF
