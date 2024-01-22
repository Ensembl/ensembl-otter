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

use List::MoreUtils qw{ uniq };

use Test::More;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::Otter qw( ^db_or_skipall );
use Test::Otter::Accessions;
use Test::SetupLog4perl;
use OtterTest::AccessionTypeCache;

use Hum::Sequence;

my $module;
BEGIN {
    $module = 'Bio::Otter::Lace::OnTheFly::QueryValidator';
    use_ok($module);
}

critic_module_ok($module);

my $_at_cache = OtterTest::AccessionTypeCache->new();
my $problem_report_cb = sub {
    my ($msgs) = @_;
    map { diag("QV ", $_, ": ", $msgs->{$_}) if $msgs->{$_} } keys %$msgs;
};
my $long_query_cb = sub { diag("QV long q: ", shift, "(", shift, ")"); };

my $ta_factory = Test::Otter::Accessions->new;
my $ta_acc_specs = $ta_factory->accessions;
my @acc_names =    $ta_factory->accession_names;

# Ad hoc - unknown to archives
my $seq = Hum::Sequence->new;
$seq->name('TESTSEQ');
$seq->sequence_string('GATTACCAAA');
$seq->type('OTF_AdHoc_DNA');

my @exp_names =
    uniq
    map  { $_->{acc_sv} }
    grep { my $m = $_->{mm_db}; my $c = $_->{currency}; $m and $m ne 'refseq' and $c and $c eq 'current' }
    @$ta_acc_specs;

push @exp_names, 'TESTSEQ';
@exp_names = sort @exp_names;

my $qv = $module->new(
    accession_type_cache => $_at_cache,
    problem_report_cb    => $problem_report_cb,
    long_query_cb        => $long_query_cb,
    accessions           => \@acc_names,
    seqs                 => [ $seq ],
);
isa_ok($qv, $module);

my $cseqs = $qv->confirmed_seqs;
ok($cseqs, 'Got confirmed seqs');
my @names = sort map { $_->name } @{$cseqs->seqs};
is_deeply(\@names, \@exp_names, 'Seqs as expected');
foreach my $n (@names) {
    ok($cseqs->seqs_by_name->{$n}->sequence_string, "$n has sequence");
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
