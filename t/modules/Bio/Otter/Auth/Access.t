#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use YAML qw( Dump Load );
use Try::Tiny;

use Test::Otter qw( try_err );

use Bio::Otter::Server::Config;
use Bio::Otter::Auth::Access;

my $BOAA = 'Bio::Otter::Auth::Access';

sub main {
    my @t = qw( species_groups_tt user_groups_tt legacy_tt dslist_tt dup_tt );
    plan tests => scalar @t;

    foreach my $subt (@t) {
        subtest $subt => main->can($subt);
    }

    return 0;
}

exit main();


our $_SP_DAT;
sub try_load {
    my ($yaml) = @_;
    my $data = Load($yaml);

    $_SP_DAT ||= Bio::Otter::Server::Config->SpeciesDat;
    # rely on qw( human mouse human_test ) existing

    return try { Bio::Otter::Auth::Access->new($data, $_SP_DAT) } catch { $_ };
}


sub species_groups_tt {
    plan tests => 4;

    like(try_load(<<'INPUT'), qr{Unknown dataset 'dinosaur' .* under species_groups/bogus}, 'dinosaur');
---
species_groups:
  main:
    - human
    - mouse
  bogus:
    - human_test
    - dinosaur
INPUT

    like(try_load(<<'INPUT'), qr{Cannot resolve unknown species_group weird .* under species_groups/dev}, ':weird group');
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

    like(try_load(<<'INPUT'), qr{Loop detected while resolving species_group dev .* under species_groups/dev}, 'loopygroup');
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

    isa_ok(try_load(<<'INPUT'), 'Bio::Otter::Auth::Access');
---
species_groups:
  main:
    - human
    - mouse
  dev:
    - human_test
    - :main
user_groups: {}
INPUT

    return;
}


# Demonstrate the object working normally
sub user_groups_tt {
    plan tests => 21;

    my $acc = try_load(<<'INPUT');
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
  ug2:
    read:
      - :main
    write:
      - sheep
    users:
      - Shaun
INPUT

    isa_ok($acc, 'Bio::Otter::Auth::Access') or die "got $acc";
    is_deeply([ sort keys %{ $acc->all_users } ], # keys are lowercased
              [qw[ alice bob shaun ]], 'get all users (keys)');
    is_deeply([ sort map { $_->email } values %{ $acc->all_users } ], # values are not
              [qw[ Shaun alice bob ]], 'get all users (values)');

    is($acc->user('zebby'), undef, 'no zebby here');
    isa_ok($acc->user('alice'), 'Bio::Otter::Auth::User', 'alice');

    is_deeply(__user_to_datasetnames($acc->user('alice'), 'write_datasets'),
              {qw{ human human  mouse mouse }},
              'alice writes');
    is_deeply(__user_to_datasetnames($acc->user('alice'), 'read_datasets'),
              {}, 'alice reads (nothing)');

    is_deeply(__user_to_datasetnames($acc->user('bob'), 'write_datasets'),
              {qw{ human human  human_test human_test  mouse mouse }},
              'bob writes');

    is($acc->user('elsie'), undef, 'unlisted user address rejected');

    isa_ok($acc->user('BOB'), 'Bio::Otter::Auth::User', 'BOB: downcasing find');
    isa_ok($acc->user('Bob')->write_dataset('human_test'),
           'Bio::Otter::SpeciesDat::DataSet', 'Bob writes human_test');

    my $shaun = $acc->user('shaun');
    is_deeply(__user_to_datasetnames($shaun, 'write_datasets'),
              {qw{ sheep sheep }}, 'shaun writes');
    is_deeply(__user_to_datasetnames($shaun, 'read_datasets'),
              {qw{ human human  mouse mouse }}, 'shaun reads');
    is_deeply(__user_to_datasetnames($shaun, 'all_datasets'),
              {qw{ human human  mouse mouse  sheep sheep }}, 'shaun can see');

    is($shaun->write_dataset('sheep')->READONLY, 0,
       'shaun: sheep not readonly');
    is($shaun->read_dataset('human')->READONLY, 1,
       'shaun: human readonly');
    is($shaun->write_dataset('human'), undef, 'shaun: no human write');
    my @shaun_all = values %{ $shaun->all_datasets };
    my @shaun_write = grep { ! $_->READONLY } @shaun_all;
    is_deeply({ all => scalar @shaun_all, write => scalar @shaun_write },
              { all => 3, write => 1 }, 'shaun dataset count from all');

    # For regression of forgotten-Access due to weakened $self->{_access}
    my ($any_real_username) = keys
      %{ Bio::Otter::Server::Config->Access->all_users };
    is(try_err {
        my $u = Bio::Otter::Server::Config->Access->user($any_real_username);
        $u->all_datasets; 'ok' },
       'ok', 'multi-statement chained call');


    like(try_load(<<'INPUT'), qr{UserGroup->new: unexpected subkeys \(frobnitz\) .* under user_groups/odd}, 'oddness');
---
species_groups: {}
user_groups:
  odd:
    frobnitz: should not be here
    users:
      - bob
INPUT


    like(try_load(<<'INPUT'), qr{Empty user spec for alice - trailing : in YAML\? .* under user_groups/colon}, 'trail:');
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


sub dslist_tt {
    plan tests => 3;

    my $acc = try_load(<<'INPUT');
---
species_groups:
  qux:
    - human
    - mouse
user_groups: {}
INPUT

    like(try_err { Bio::Otter::Auth::DsList->new($acc, 'bar') },
         qr{new needs arrayref of dataset names}, 'DsList->new arrayref');

    my $ds1 = Bio::Otter::Auth::DsList->new($acc, [qw[ foo bar baz :qux fum ]]);
    my @drop;
    my %drop = (foo => undef, baz => 1, human => 1, whumpf => 1);
    my $ds2 = $ds1->clone_without(\%drop, \@drop);
    is_deeply([ $ds2->raw_names ], [qw[ bar mouse fum ]], 'clone_without');
    is_deeply(\@drop, [qw[ foo baz human ]], 'dropped');

    return;
}


sub dup_tt {
    plan tests => 16;

    like(try_load(<<'INPUT'), qr{Duplicate user bob .* under user_groups/(one|two)}, 'bob dup');
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


    like(try_load(<<'INPUT'), qr{Duplicate user bob .* under user_groups/one}i, 'Bob/BOB dup');
---
species_groups: {}
user_groups:
  one:
    users:
      - BOB
      - Bob
INPUT

    my $dup_ds = try_load(<<'INPUT');
---
species_groups: {}
user_groups:
  ug1:
    write:
      - human
    users:
      - alice:
          write:
            - human
      - bob
INPUT

    isa_ok($dup_ds, $BOAA, 'alice has human*2');

    # two permits to write a dataset is fine
    is_deeply(scalar $dup_ds->user('alice')->all_datasets,
              scalar $dup_ds->user('bob')->all_datasets,
              'human*2 = human*1');

    my $ds_rwro = try_load(<<'INPUT');
---
species_groups: {}
user_groups:
  ug1:
    write:
      - human
    users:
      - chuck:
          read:
            - human
INPUT
    my $ds_rorw = try_load(<<'INPUT');
---
species_groups: {}
user_groups:
  ug1:
    read:
      - human
    users:
      - chuck:
          write:
            - human
INPUT
    foreach my $pair ([ rorw => $ds_rorw ],
                      [ rwro => $ds_rwro ]) {
        my ($name, $acc) = @$pair;
        my @warn;
        local $SIG{__WARN__} = sub { my ($msg) = @_; push @warn, $msg };
        isa_ok($acc, $BOAA, $name);
        my $user = $acc->user('chuck');
        is_deeply($user->write_datasets, {}, "$name: no write");
        my $ro = $user->read_datasets;
        ok(try { $ro->{human}->READONLY }, "$name: human is r-o");
        is_deeply($user->all_datasets,
                  { human => $ro->{human} }, "$name: nothing else");
        is(scalar @warn, 1, 'warned once');
        like($warn[0],
             qr{^User chuck has both read\+write on \(human\),}, 'warn text');
    }

    return;
}

