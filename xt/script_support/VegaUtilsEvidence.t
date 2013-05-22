#!/usr/bin/env perl

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
