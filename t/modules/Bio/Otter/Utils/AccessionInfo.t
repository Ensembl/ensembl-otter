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

use Test::Otter::Accessions;

use Data::Dumper;
use Test::More;

my ($module, $driver_module, $bulk_driver_module);
BEGIN {
    $module        = 'Bio::Otter::Utils::AccessionInfo';
    $driver_module = 'Bio::Otter::Utils::MM';
    $bulk_driver_module = 'Bio::Otter::Utils::BulkMM';
    use_ok($module);
    use_ok($driver_module);
    use_ok($bulk_driver_module);
}

critic_module_ok($module);
critic_module_ok($driver_module);
critic_module_ok($bulk_driver_module);

my $ai = new_ok($module);

my @valid_accs = qw(AK122591.2 AK122591);
my @invalid_accs = qw(AK122591.1 XYZ123456 ERS000123 NM_001142769.1); # one old SV, one nonsense, one SRA, one refseq

my $results = $ai->get_accession_types([@valid_accs, @invalid_accs]);
is(ref($results), 'HASH', 'results hash');

foreach my $valid ( @valid_accs ) {
    my $at = $results->{$valid};
    ok($at, "$valid: have result");
    ok($at->{taxon_list}, "$valid: has taxon_list");
    note("\ttaxon_list:\t", $at->{taxon_list});
    note("\tdescription:\t\t", $at->{description});
}

foreach my $invalid ( @invalid_accs ) {
    my $at = $results->{$invalid};
    ok(not($at), "$invalid: no result");
}

# Singleton
my $acc = $valid_accs[1];
my $s_results = $ai->get_accession_types([$acc]);
is(ref($s_results), 'HASH', 's_results hash');
ok($s_results->{$acc}, 'result is for singleton acc');

my $s_acc = $valid_accs[0];
my $seq_results = $ai->get_accession_info([$s_acc]);
is(ref($seq_results), 'HASH', 'seq_results hash');
ok($seq_results->{$s_acc}, 'result is for singleton acc');
note('seq_result: ', Dumper($seq_results->{$s_acc}));

# Empty
my $e_results = $ai->get_accession_types([]);
is(ref($e_results), 'HASH', 'e_results hash');
ok(not(%$e_results), 'result is empty');

# New central list
my $ta_factory = Test::Otter::Accessions->new;
my $ta_acc_specs = $ta_factory->accessions;
my @ta_accs      = $ta_factory->accession_names;
my $ta_results = $ai->get_accession_types(\@ta_accs);
is(ref($ta_results), 'HASH', 'ta_results hash');

foreach my $ta_acc_spec (@$ta_acc_specs) {
    my $query = $ta_acc_spec->{query};
    subtest $query => sub {
        my $result = $ta_results->{$query};
        if ($ta_acc_spec->{evi_type}) {
            foreach my $key (qw{ acc_sv evi_type source }) {
                is($result->{$key}, $ta_acc_spec->{$key}, "$key");
            }
        } else {
            is($result, undef, 'no result');
        }
        done_testing;
    };
}

# New interface
$ai->db_categories([qw(
    emblnew
    emblrelease
    uniprot
    uniprot_archive
    refseq
)]);
my $info_results = do {
    local $SIG{__WARN__} = \&__muffle_badquery;
    $ai->get_accession_info(\@ta_accs);
};
is(ref($info_results), 'HASH', 'info_results hash');
foreach my $ta_acc_spec (@$ta_acc_specs) {
    my $query = $ta_acc_spec->{query};
    subtest $query => sub {
        my $result = $info_results->{$query};
        if ($ta_acc_spec->{mm_db}) {
            $result ||= {};
            foreach my $key (qw{ acc_sv evi_type source currency }) {
                is($result->{$key}, $ta_acc_spec->{$key}, "$key") if $ta_acc_spec->{$key};
            }
            is(length($result->{sequence}), $result->{sequence_length}, 'seq_length');
        } else {
            is($result, undef, 'no result');
        }
        done_testing;
    };
}

sub __muffle_badquery {
    my ($msg) = @_;
    warn "$msg" unless $msg =~ /^Bad query: '\S+' \(sv_search is off\) at /;
    return;
}


my %taxon_info = (
         9606 => { scientific_name => 'Homo sapiens', common_name => 'man' },
        10090 => { scientific_name => 'Mus musculus', common_name => 'mouse' },
        90988 => { scientific_name => 'Pimephales promelas' },
    123456789 => undef,
    );

my $ti = $ai->get_taxonomy_info([keys %taxon_info]);
is(ref($ti), 'ARRAY', 'get_taxonomy_info returns arrayref');
my %ti_results = map { $_->{id} => $_ } @$ti;
foreach my $tid (keys %taxon_info) {
    subtest "Taxon id '$tid'" => sub {
        my $result = $ti_results{$tid};
        if (my $exp = $taxon_info{$tid}) {
            $exp->{id} = $tid;
            foreach my $key (qw(id scientific_name common_name)) {
                is($result->{$key}, $exp->{$key}, "$key");
            }
        } else {
            is($result, undef, 'no_result');
        }
        done_testing;
    };
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
