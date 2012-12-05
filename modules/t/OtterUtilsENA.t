#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::ENA';
    use_ok($module);
}

critic_module_ok($module);

my $ena = $module->new;
isa_ok($ena, $module);

my @valid_accs = qw(ERS000123 SRS000012 DRS000234);
my @invalid_accs = qw(ERA000012 XYZ123456); # one submission, one nonsense

my $results = $ena->get_sample_accessions(@valid_accs, @invalid_accs);
is(ref($results), 'HASH', 'Results hash');

foreach my $valid ( @valid_accs ) {
    my $sample = $results->{$valid};
    ok($sample, "$valid: have result");
    ok($sample->{taxon_id}, "$valid: has taxon_id");
    note("\ttaxon_id:\t", $sample->{taxon_id});
    note("\talias:\t\t", $sample->{alias});
    note("\ttitle:\t\t", $sample->{title});
}

foreach my $invalid ( @invalid_accs ) {
    my $sample = $results->{$invalid};
    ok(not($sample), "$invalid: no result");
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
