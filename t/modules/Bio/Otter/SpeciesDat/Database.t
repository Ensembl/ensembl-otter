#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use YAML qw( Dump Load );
use Try::Tiny;

use Bio::Otter::Server::Config;
use Bio::Otter::SpeciesDat::Database;

my $BOSdb = 'Bio::Otter::SpeciesDat::Database';

sub main {
    my @t = qw( small_tt various_fail_tt real_tt );
    plan tests => scalar @t;

    foreach my $subt (@t) {
        subtest $subt => main->can($subt);
    }

    return 0;
}

exit main();


sub try_load {
    my ($yaml) = @_;
    my $data = Load($yaml);
    return try {
        Bio::Otter::SpeciesDat::Database->new_many_from_dbspec($data->{dbspec});
    } catch {
        "ERR:$_";
    };
}


sub small_tt {
    plan tests => 9;

    my $dbs = try_load(<<'INPUT');
---
dbspec:
  loopy:
    -alias: fruit
  fruit:
    host: tree
    port: 1234
    user: bob
    pass: sekret
INPUT

    isa_ok($dbs, 'HASH') or diag "dbs=$dbs";
    isa_ok($dbs->{loopy}, $BOSdb);
    my $fruit = $dbs->{fruit};
    isa_ok($fruit, $BOSdb);

    my $dbs_dash = try_load(<<'INPUT');
---
dbspec:
  loopy:
    -alias: fruit
  fruit:
    -host: tree
    -port: 1234
    -user: bob
    -pass: sekret
INPUT

    isa_ok($dbs_dash, 'HASH') or diag "dbs_dash=$dbs_dash";
    is_deeply($dbs_dash, $dbs, 'dbs = dbs_dash');

    my $exp_P = { host => 'tree', port => 1234, user => 'bob', pass => 'sekret' };
    is_deeply({ $fruit->params }, $exp_P, 'db->params');
    is_deeply({ host => $fruit->host, port => $fruit->port,
                user => $fruit->user, pass => $fruit->pass }, $exp_P, 'db->$key');

    is_deeply([$fruit->spec_DBI('froot', { Tangy => 1 })],
              ['DBI:mysql:host=tree;port=1234;database=froot', 'bob', 'sekret',
               { RaiseError => 1, AutoCommit => 1, PrintError => 0, Tangy => 1 }],
              'fruit->spec_DBI(...)');
    is_deeply([$fruit->spec_DBI],
              ['DBI:mysql:host=tree;port=1234', 'bob', 'sekret',
               { RaiseError => 1, AutoCommit => 1, PrintError => 0 }],
              'fruit->spec_DBI');

    return;
}


sub various_fail_tt {
    plan tests => 6;

    like(try_load(<<'INPUT'), qr{name=all_ias has alias=thing, should have nothing else}, 'ambigu-alias');
---
dbspec:
  all_ias:
    -alias: thing
    -host: cheddar
INPUT

    like(try_load(<<'INPUT'), qr{name=strange contains bad keys \(veins\) }, 'bad keys');
---
dbspec:
  strange:
    -host: cheddar
    -port: 1234
    -veins: blue
INPUT

    like(try_load(<<'INPUT'), qr{name=mixy has inconsistent -dash/}, 'mixed nodash');
---
dbspec:
  mixy:
    host: cheddar
    -port: 1234
    user: mild
INPUT

    like(try_load(<<'INPUT'), qr{name=storm has missing keys \(port\)}, 'no port');
---
dbspec:
  storm:
    -host: cheddar
    -user: cracker
INPUT

    like(try_load(<<'INPUT'), qr{Alias loopy --> fruit points nowhere}, 'bad alias');
---
dbspec:
  loopy:
    -alias: fruit
INPUT

    like(try_load(<<'INPUT'), qr{Alias loopy --> fruit points to another alias}, 'loopy');
---
dbspec:
  loopy:
    -alias: fruit
  fruit:
    -alias: cherry
  cherry:
    -host: tree
    -port: 1234
    -user: bob
INPUT

    return;
}


sub real_tt {
    plan tests => 3;
    my $BOSC = 'Bio::Otter::Server::Config';
    my $db = $BOSC->Databases;
    isa_ok($db, 'HASH') or diag "db=$db";
    isa_ok($db->{otterlive}, $BOSdb, 'otterlive');
    isa_ok($BOSC->Database('otterlive'), $BOSdb);
    return;
}
