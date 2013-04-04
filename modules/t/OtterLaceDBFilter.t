#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use File::Spec;
use File::Temp;

use Test::More;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my ($filter_module, $adaptor_module);
BEGIN {
      $filter_module  = 'Bio::Otter::Lace::DB::Filter';
      $adaptor_module = 'Bio::Otter::Lace::DB::FilterAdaptor';
      use_ok($filter_module);
      use_ok($adaptor_module);
}

critic_module_ok($filter_module);
critic_module_ok($adaptor_module);

my %f1_spec = ( filter_name => 'test', wanted => 1, done => 0, gff_file => '/aaa/bb/c1.gff' );
my $f1 = new_ok($filter_module => [ %f1_spec ]);
filter_ok ($f1, { %f1_spec, is_stored => undef }, 'from new()');

my $dbh = test_schema();
my $fa = new_ok($adaptor_module => [ $dbh ]);
ok($fa->store($f1), 'store');
is($f1->is_stored, 1, 'is_stored');

my %f2_spec = ( filter_name => 'test_too', wanted => 0, done => 0, process_gff => 1, gff_file => '/aaa/bb/c2.gff' );
my $f2 = new_ok($filter_module => [ %f2_spec ]);
filter_ok ($f2, { %f2_spec, is_stored => undef }, 'from new() 2');
ok($fa->store($f2), 'store 2');
is($f2->is_stored, 1, 'is_stored 2');

my $f1_r = $fa->fetch_by_name('test');
filter_ok($f1_r, { %f1_spec, is_stored => 1 }, 'fetch_by_name()');
isnt($f1_r, $f1, 'have new object');

my $f2_r = $fa->fetch_by_name('test_too');
filter_ok($f2_r, { %f2_spec, is_stored => 1 }, 'fetch_by_name() 2');
isnt($f2_r, $f2, 'have new object 2');

$f2->failed(1);
ok($fa->update($f2), 'update');
$f2_spec{failed} = 1;
my $f2_u = $fa->fetch_by_name('test_too');
filter_ok($f2_u, { %f2_spec, is_stored => 1 }, 'fetch_by_name() 2u');
isnt($f2_u, $f2_r, 'have new object 2u');

my @filters = $fa->fetch_all;
is(scalar(@filters), 2, 'fetch_all');
my %all_by_name = map { $_->filter_name => $_ } @filters;
filter_ok($all_by_name{'test'},     { %f1_spec, is_stored => 1 }, "fetch_all 'test'" );
filter_ok($all_by_name{'test_too'}, { %f2_spec, is_stored => 1 }, "fetch_all 'test_too'" );

my %f3_spec = ( filter_name => 'test_free', done => 0, process_gff => 1, gff_file => '/aaa/bb/c3.gff' );
my $f3 = new_ok($filter_module => [ %f3_spec ]);
filter_ok ($f3, { %f3_spec, is_stored => undef }, 'from new() 3');
ok($fa->store($f3), 'store 3');
is($f3->is_stored, 1, 'is_stored 3');

my @some = $fa->fetch_where('done = 0 and process_gff = 1');
is(scalar(@some), 2, 'fetch_where');
my %some_by_name = map { $_->filter_name => $_ } @some;
filter_ok($some_by_name{'test_too'},  { %f2_spec, is_stored => 1 }, "fetch_all 'test_too'" );
filter_ok($some_by_name{'test_free'}, { %f3_spec, is_stored => 1 }, "fetch_all 'test_free'" );

ok($fa->delete($f2), 'delete 2');
my @fewer = $fa->fetch_all;
is(scalar(@fewer), 2, 'fetch_all fewer');
my %fewer_by_name = map { $_->filter_name => $_ } @fewer;
filter_ok($fewer_by_name{'test'},      { %f1_spec, is_stored => 1 }, "fetch_all 'test'" );
filter_ok($fewer_by_name{'test_free'}, { %f3_spec, is_stored => 1 }, "fetch_all 'test_free'" );

done_testing;
cleanup_temp();

sub filter_ok {
    my ($result, $expected, $desc) = @_;
    subtest $desc => sub {
        isa_ok($result, $filter_module, 'filter object');
        foreach my $attrib ( keys %$expected ) {
            is($result->$attrib(), $expected->{$attrib}, $attrib);
        }
        done_testing;
    };
    return;
}

my ($tmp_dir, $sqlite);

sub test_schema {
    $tmp_dir = File::Temp->newdir('OtterLaceDBFilter.t.XXXXXX', TMPDIR => 1, CLEANUP => 0);
    $sqlite  = File::Spec->catfile($tmp_dir, 'otter.sqlite');
    note "SQLite db is: $sqlite";

    my $dbh = DBI->connect("dbi:SQLite:dbname=${sqlite}",
                           undef,
                           undef,
                           {
                               RaiseError => 1,
                               AutoCommit => 1,
                           });

    $dbh->do(q{
CREATE TABLE otter_filter (
            filter_name     TEXT PRIMARY KEY
            , wanted        INTEGER DEFAULT 0
            , failed        INTEGER DEFAULT 0
            , done          INTEGER DEFAULT 0
            , gff_file      TEXT
            , process_gff   INTEGER DEFAULT 0
        );
              });

    return $dbh;
}

sub cleanup_temp {
    unlink $sqlite;
    rmdir  $tmp_dir;
    return;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
