#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use FindBin qw($Bin);
use lib "$Bin/lib";
use OtterTest::AccessionTypeCache;

use Test::More;

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

my $qv = $module->new(
    accession_type_cache => $_at_cache,
    problem_report_cb    => $problem_report_cb,
    long_query_cb        => $long_query_cb,
    accessions           => [ qw( AL542381.3 ERS000123 ) ],
);
isa_ok($qv, $module);

my $seqs = $qv->confirmed_seqs;
ok($seqs, 'Got confirmed seqs');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
