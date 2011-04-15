#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{TEAM_TOOLS}}/t/tlib";
use CriticModule;

use Test::More tests => 8;

my $module;
BEGIN {
    $module = 'Bio::Vega::Utils::Evidence';
    use_ok($module, qw/get_accession_type/); 
}

critic_module_ok($module);

# Basics

my @r = get_accession_type('AA913908.1');
ok(scalar(@r), 'get versioned accession');

my ($type, $acc_sv, $src_db, $seq_len, $taxon_list, $desc) = @r;
is ($type, 'EST');
is ($acc_sv, 'AA913908.1');

@r = get_accession_type('AA913908');
ok(scalar(@r), 'get unversioned accession');

($type, $acc_sv, $src_db, $seq_len, $taxon_list, $desc) = @r;
is ($type, 'EST');
is ($acc_sv, 'AA913908.1');

1;

# Local Variables:
# mode: perl
# End:

# EOF
