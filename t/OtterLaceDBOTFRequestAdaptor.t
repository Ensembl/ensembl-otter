#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

# FIXME: lots of boilerplate here.

use Test::Otter qw( ^data_dir_or_skipall ); # also finds test libraries
use OtterTest::DB;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Bio::Otter::Lace::DB::OTFRequest;

my $adaptor_module;
BEGIN {
      $adaptor_module = 'Bio::Otter::Lace::DB::OTFRequestAdaptor';
      use_ok($adaptor_module);
}

critic_module_ok($adaptor_module);

my $test_db = OtterTest::DB->new;
my $ra = new_ok($adaptor_module => [ $test_db->dbh ]);

my $obj_class = 'Bio::Otter::Lace::DB::OTFRequest';
my @req;
$req[0] = $obj_class->new(
    logic_name  => 'OTFRequestAdaptorTest_EST',
    target_start=> 12446,
    command     => 'exonerate',
    args        => { '--opt' => 'THIS', '--flag' => undef },
    );
$req[1] = $obj_class->new(
    logic_name  => 'OTFRequestAdaptorTest_Protein',
    command     => 'crossmatch',
    args        => { foo => 1, baa => undef, },
    );

foreach my $i ( 0..1 ) {
    ok($ra->store($req[$i]), "store $i");
    is($req[$i]->is_stored, 1, "is_stored $i");
    note("id for $i is ", $req[$i]->id);
}

my $rbln = $ra->fetch_by_logic_name('OTFRequestAdaptorTest_Protein');
isa_ok($rbln, $obj_class, 'fetch_by_logic_name (exists)');
request_ok($rbln, $req[1], 'fetch_by_logic_name (matches)');

$req[0]->n_hits(3);
$req[0]->completed(1);
$req[0]->missed_hits(['AB1234.5', 'CDEFG.6']);

ok($ra->update($req[0]), "update");

$rbln = $ra->fetch_by_logic_name('OTFRequestAdaptorTest_EST', 1);
isa_ok($rbln, $obj_class, 'after_update (exists)');
request_ok($rbln, $req[0], 'after_update (matches)');

done_testing;

sub request_ok {
    my ($result, $expected, $desc) = @_;
    subtest $desc => sub {
        isa_ok($result, ref($expected), 'object class');
        foreach my $attrib ( keys %$expected ) {
            next if $attrib eq 'args';
            next if $attrib eq 'missed_hits';
            is($result->$attrib(), $expected->$attrib(), $attrib);
        }
        if (my $ea = $expected->{args}) {
            subtest "${desc}:args" => sub {
                my $ra = $result->args;
                unless ($ra) {
                    fail "no args";
                    return;
                }
                while (my ($key, $value) = each %$ea) {
                    ok(exists($ra->{$key}), "'$key' exists");
                    is($ra->{$key}, $value, "'$key' value");
                }
                done_testing;
            };
        }
        if (my $emh = $expected->{missed_hits}) {
            subtest "${desc}:missed_hits" => sub {
                my $rmh = $result->missed_hits;
                unless ($rmh) {
                    fail "no missed_hits";
                    return;
                }
                my @r_sorted = sort(@$rmh);
                is (scalar(@r_sorted), scalar(@$emh), 'n_missed_hits');
                foreach my $q (sort @$emh) {
                    my $r = shift @r_sorted;
                    is($r, $q, "query_name");
                }
                done_testing;
            };
        }
        done_testing;
    };
    return;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
