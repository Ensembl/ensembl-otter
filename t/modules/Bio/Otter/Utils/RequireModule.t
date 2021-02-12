#!/usr/bin/env perl
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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;
use Try::Tiny;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::RequireModule';
    use_ok($module, 'require_module');
}
critic_module_ok($module);

try_require(module => $module,    exp_live => 1, exp_load => 1, desc => 'already loaded');
try_require(module => 'Net::FTP', exp_live => 1, exp_load => 1, desc => 'core module');

try_require(module => 'Not::Known',
            exp_live => undef, exp_error => qr/Couldn't load 'Not::Known'/, desc => 'not found');

try_require(module => 'Not::Known', opts => { no_die => 1 },
            exp_live => 1, exp_error => undef, desc => 'not found - no_die');

try_require(module => 'Not::Known', exp_error_ref => qr(Can't locate Not/Known.pm),
            exp_live => 1, exp_error => undef, desc => 'not found - error_ref');
try_require(module => 'Net::POP3',  exp_error_ref => undef, exp_load => 1,
            exp_live => 1, exp_error => undef, desc => 'found - error_ref');

done_testing;

sub try_require {
    my %args = @_;
    my (         $module, $opts, $exp_live, $exp_load, $exp_error, $exp_error_ref, $desc) =
        @args{qw( module   opts   exp_live   exp_load   exp_error   exp_error_ref   desc )};

    $opts ||= {};
    my $do_error_ref = exists $args{exp_error_ref};

    subtest "$desc [$module]" => sub {
        my $file = (join ('/', split ('::', $module) ) ) . '.pm';
        note("$module already in %INC") if $INC{$file};

        my $catch_error;
        if ($do_error_ref) {
            $opts->{error_ref} = \$catch_error;
        }

        my ($okay, $retval, $error);
        try {
            $retval = require_module($module, %$opts);
            $okay = 1;
        } catch {
            $error = $_;
        };

        is($okay,   $exp_live, 'live or die');
        is($retval, $exp_load ? $module : undef, 'return value');
        if ($exp_load) {
            ok($INC{$file}, 'in INC');
        }
        if ($exp_error) {
            like($error, $exp_error, 'error thrown');
        } else {
            ok(not($error), 'no error thrown');
        }
        if ($do_error_ref) {
            if ($exp_error_ref) {
                like($catch_error, $exp_error_ref, 'error_ref matches');
            } else {
                ok(not($catch_error), 'error_ref undef');
            }
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

