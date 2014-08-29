#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use YAML qw( Dump Load );
use Try::Tiny;

use Bio::Otter::Server::Config;
use Bio::Otter::Auth::Access;

sub main {
    my @t = qw( species_groups_tt user_groups_tt legacy_tt various_fail_tt );
    plan tests => scalar @t;

    foreach my $subt (@t) {
        subtest $subt => main->can($subt);
    }

    return 0;
}

exit main();


my $_SP_DAT;
sub try_load {
    my ($yaml) = @_;
    my $data = Load($yaml);

    $_SP_DAT ||= Bio::Otter::Server::Config->SpeciesDat;
    # rely on qw( human mouse human_test ) existing

    return try { Bio::Otter::Auth::Access->new($data, $_SP_DAT) } catch { $_ };
}


sub species_groups_tt {
    plan tests => 4;

    like(try_load(<<INPUT), qr{Unknown dataset 'dinosaur' .* under species_groups/bogus}, 'dinosaur');
---
species_groups:
  main:
    - human
    - mouse
  bogus:
    - human_test
    - dinosaur
INPUT

    like(try_load(<<INPUT), qr{Cannot resolve unknown species_group weird .* under species_groups/dev}, ':weird group');
---
species_groups:
  main:
    - human
    - mouse
  dev:
    - human_test
    - :weird
    - :main
INPUT

    like(try_load(<<INPUT), qr{Loop detected while resolving species_group dev .* under species_groups/dev}, 'loopygroup');
---
species_groups:
  main:
    - human
    - mouse
    - :dev
  dev:
    - human_test
    - :main
INPUT

    isa_ok(try_load(<<INPUT), 'Bio::Otter::Auth::Access');
---
species_groups:
  main:
    - human
    - mouse
  dev:
    - human_test
    - :main
INPUT

    return;
}


sub user_groups_tt {
    plan tests => 8;

    my $acc = try_load(<<INPUT);
---
species_groups:
  main:
    - human
    - mouse
  dev:
    - human_test
    - :main
user_groups:
  ug1:
    write:
      - :main
    users:
      - alice
      - bob:
          write:
            - :dev
INPUT

    isa_ok($acc, 'Bio::Otter::Auth::Access');
    is($acc->user('zebby'), undef, 'no zebby here');
    isa_ok($acc->user('alice'), 'Bio::Otter::Auth::User', 'alice');

    is_deeply(__user_to_datasetnames($acc->user('alice'), 'write_datasets'),
              {qw{ human human  mouse mouse }},
              'alice writes');

    is_deeply(__user_to_datasetnames($acc->user('bob'), 'write_datasets'),
              {qw{ human human  human_test human_test  mouse mouse }},
              'bob writes');


    like(try_load(<<INPUT), qr{Duplicate user bob .* under user_groups/(one|two)}, 'bob dup');
---
species_groups: {}
user_groups:
  one:
    users:
      - bob
  two:
    users:
      - bob
INPUT


    like(try_load(<<INPUT), qr{UserGroup->new: unexpected subkeys \(frobnitz\) .* under user_groups/odd}, 'oddness');
---
species_groups: {}
user_groups:
  odd:
    frobnitz: should not be here
    users:
      - bob
INPUT


    like(try_load(<<INPUT), qr{Empty user spec for alice - trailing : in YAML\? .* under user_groups/colon}, 'trail:');
---
species_groups: {}
user_groups:
  colon:
    users:
      - alice:
      - bob
INPUT

    return;
}

sub __user_to_datasetnames {
    my ($user, $method) = @_;
    my $ds_hash = $user->$method;
    my %ds_name;
    @ds_name{ keys %$ds_hash } = map { $_->name } values %$ds_hash;
    return \%ds_name;
}


sub legacy_tt {
    plan tests => 2;

    my $acc = try_load(<<'INPUT');
---
species_groups:
  main:
    - human
    - mouse
    - zebrafish
  dev:
    - human_test
    - human_dev
user_groups:
  us:
    write:
      - :main
    users:
      - alice:
          write:
            - :dev
      - bob
  them:
    write:
      - zebrafish
    users:
      - Charlie.Bruin@example.org
      - Daisy.Clue@example.net
INPUT

    if (!isa_ok($acc, 'Bio::Otter::Auth::Access')) {
        diag $acc;
        return; # subtest bail out
    }

    my $want = Load(<<'HASH');
---
alice:
  human_test: 1
  human_dev: 1
charlie.bruin@example.org:
  zebrafish: 1
daisy.clue@example.net:
  zebrafish: 1
HASH

    is_deeply($acc->legacy_users_hash, $want, 'staff hidden');

    return;
}


sub try_err(&) {
    my ($code) = @_;
    return try { $code->() } catch {"ERR:$_"};
}

sub various_fail_tt {
    plan tests => 1;
    like(try_err { Bio::Otter::Auth::DsList->new([ 'blah' ], 'bar') },
         qr{new needs arrayref of dataset names}, 'DsList->new arrayref');
    return;
}
