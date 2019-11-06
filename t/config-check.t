#! /usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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
