#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

# FIXME: copy-and-paste from OtterLaceOnTheFly.t
use File::Temp;
use FindBin qw($Bin);
use lib "$Bin/lib";
use OtterTest::Client;
use Bio::Otter::Lace::AccessionTypeCache;
use Bio::Otter::Lace::DB;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Lace::OnTheFly::QueryValidator';
    use_ok($module);
}

critic_module_ok($module);

# FIXME: copy-and-paste from OtterLaceOnTheFly.t
local $ENV{DOCUMENT_ROOT} = '/nfs/WWWdev/SANGER_docs/htdocs';
my $tmp_dir = File::Temp->newdir('OtterLaceOTFQueryValidator.t.XXXXXX');
my $at_cache = setup_accession_type_cache($tmp_dir->dirname);
my $problem_report_cb = sub {
    my ($msgs) = @_;
    map { diag("QV ", $_, ": ", $msgs->{$_}) if $msgs->{$_} } keys %$msgs;
};
my $long_query_cb = sub { diag("QV long q: ", shift, "(", shift, ")"); };

my $qv = $module->new(
    accession_type_cache => $at_cache,
    problem_report_cb    => $problem_report_cb,
    long_query_cb        => $long_query_cb,
    accessions           => [ qw( AL542381.3 ERS000123 ) ],
);
isa_ok($qv, $module);

my $seqs = $qv->confirmed_seqs;
ok($seqs, 'Got confirmed seqs');

done_testing;

# FIXME: copy-and-paste from OtterLaceOnTheFly.t
sub setup_accession_type_cache {
    my $tmp_dir = shift;
    my $test_client = OtterTest::Client->new;
    my $test_db = Bio::Otter::Lace::DB->new($tmp_dir);
    my $at_cache = Bio::Otter::Lace::AccessionTypeCache->new;
    $at_cache->Client($test_client);
    $at_cache->DB($test_db);
    return $at_cache;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
