#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Otter qw( ^data_dir_or_skipall try_err );
use Time::HiRes qw( gettimeofday tv_interval );

use Bio::Otter::Server::Config;

my $T_LIM = 0.2; # limit chosen arbitrarily, could fail by NFS lag

sub main {
    plan tests => 4;

    my @warn;
    local $SIG{__WARN__} = sub { my ($msg) = @_; push @warn, $msg };

    my $t0 = [gettimeofday];
    my $acc = try_err { Bio::Otter::Server::Config->Access };
    # Needs access.yaml species.dat databases.yaml

    isa_ok($acc, 'Bio::Otter::Auth::Access', 'access.yaml object')
      or diag explain { acc => $acc };

    my $t = tv_interval($t0);
    cmp_ok($t, '<', $T_LIM, 'config loaded rapidly');
    note sprintf("%.3fs", $t);

    my $users = $acc->all_users;
    cmp_ok(scalar keys %$users, '>', 3, 'contains some users');

    foreach my $user (values %$users) {
        my $dshash = $user->all_datasets;
    }
    is(scalar @warn, 0, 'get datasets for each, no warnings')
      or diag explain { warn => \@warn };

    return 0;
}

exit main();
