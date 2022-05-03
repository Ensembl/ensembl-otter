#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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

use Test::More;
use YAML qw( Dump Load );
use Try::Tiny;

# Some tests could run without data_dir...
use Test::Otter qw( ^data_dir_or_skipall try_err );

use Bio::Otter::Server::Config;
use Bio::Otter::SpeciesDat::Database;

my $BOSdb = 'Bio::Otter::SpeciesDat::Database';
my $BOSC = 'Bio::Otter::Server::Config';

sub main {
    my @t = qw( noDBI_tt small_tt various_fail_tt real_tt );
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


sub noDBI_tt {
    plan tests => 2;

    {
        local $ENV{'ANACODE_SERVER_CONFIG'} = '/absent';
        local $ENV{'DOCUMENT_ROOT'} = '/absent/htdocs' if $ENV{'DOCUMENT_ROOT'};
        like(try_err { $BOSC->Database('human') },
             qr{Database passwords not available: data_dir /absent},
             'tell absence of DBI params');
    }

    isa_ok(try_err { $BOSC->Database('otterlive') },
           $BOSdb, 'databases.yaml:human');

    return;
}

sub small_tt {
    plan tests => 13;

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

    my $checkp = try_load(<<'INPUT');
---
dbspec:
  withpass:
    host: foo
    port: 1234
    user: bob
    pass: sekret
  nopass:
    host: foo
    port: 1234
    user: dod
INPUT

    my $checkp_pass =
      { map { $_ => [ $checkp->{$_}->pass_maybe('PaSS') ] } qw( withpass nopass ) };
    is_deeply($checkp_pass,
              { withpass => [ PaSS => 'sekret' ], nopass => [] },
              'pass_maybe');

    my $romap = try_load(<<'INPUT');
---
dbspec:
  rwrw:
    host: foo
    port: 1234
    user: bob
    ro_dbspec: roro
  roro:
    host: bar
    port: 1234
    user: dunk
INPUT
    my $rwrw = $romap->{rwrw};
    my $roro = $romap->{  $rwrw->ro_dbspec  }; # how it's used in BOS:DataSet
    is($rwrw->user, 'bob', 'rwrw user');
    is($roro->user, 'dunk', 'roro user');
    is($roro->ro_dbspec, undef, 'roro has no ro_dbspec');

    return;
}


sub various_fail_tt {
    plan tests => 8;

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

    like(try_load(<<'INPUT'), qr{rwrw\{ro_dbspec\} = roro points nowhere}, 'bad ro_dbspec');
---
dbspec:
  rwrw:
    host: foo
    port: 1234
    user: bob
    ro_dbspec: roro
INPUT

    like(try_load(<<'INPUT'), qr{rwrw\{ro_dbspec\} = rwrw has another}, 'lame ro_dbspec');
---
dbspec:
  rwrw:
    host: foo
    port: 1234
    user: bob
    ro_dbspec: rwrw
INPUT

    return;
}


sub real_tt {
    plan tests => 3;
    my $db = $BOSC->Databases;
    isa_ok($db, 'HASH') or diag "db=$db";
    isa_ok($db->{otterlive}, $BOSdb, 'otterlive');
    isa_ok($BOSC->Database('otterlive'), $BOSdb);
    return;
}
