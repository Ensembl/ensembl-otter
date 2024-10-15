#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
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

use Test::More tests => 6;
use File::Temp 'tempdir';
use File::Slurp qw( slurp write_file );
use Try::Tiny;


sub main {
    require_ok('Bio::Otter::Lace::Defaults')
      or die 'Code fail';

    subtest correct_cfg => \&correct_cfg_tt
      or die 'Abort! Do not overwrite my real config';

    subtest defaults => \&defaults_tt;
    subtest makenew => \&makenew_tt;
    subtest async_edit => \&async_edit_tt;
    subtest multiwrite => \&multiwrite_tt;

    return ();
}


{
    my $tmpdir;
    sub test_config {
        my ($sfx) = @_;
        $tmpdir ||= tempdir('BOLD.t.XXXXXX', TMPDIR => 1, CLEANUP => 1);
        my $fn = "$tmpdir/otter_test_config.$sfx"; # often doesn't exist
        return Bio::Otter::Lace::Defaults::testmode_redirect_reset($fn);
    }
}

sub getopt_with_args {
    my (@new_argv) = @_;
    my @dogo_arg;
    @dogo_arg = @{ pop @new_argv } if ref($new_argv[-1]);
    local @ARGV = @new_argv;
    return Bio::Otter::Lace::Defaults::do_getopt(@dogo_arg);
}

sub getcfg { # like ->config_value but bypassing Bio::Otter::Lace::Client
    my ($key, $section) = @_;
    $section ||= 'client';
    return Bio::Otter::Lace::Defaults::config_value('client', $key);
}

sub putcfg { goto &Bio::Otter::Lace::Defaults::set_and_save } # short name

sub wholecfg {
    my $fn = Bio::Otter::Lace::Defaults::user_config_filename();
    return slurp($fn);
}


sub correct_cfg_tt {
    plan tests => 2;

    my $orig_ucfg_fn = Bio::Otter::Lace::Defaults::user_config_filename();
    like($orig_ucfg_fn, qr{^/.*/\.otter(_config|/config\.ini)$},
         "real user config filename: $orig_ucfg_fn");

    test_config('tmpcfg');

    like(Bio::Otter::Lace::Defaults::user_config_filename(),
         qr{test_config}, "fake-tmp user config filename");

    return ();
}

sub defaults_tt {
    plan tests => 6;
    test_config('defaults_tt');

    # getopt 0 times
    like((try { getcfg('url') } catch {"ERR:$_"}),
         qr{^ERR:Not ready}, "Reject early config_value");
    like((try { putcfg(client => author => 'alice') } catch {"ERR:$_"}),
         qr{^ERR:Not ready}, "Reject early set_and_save");

    # getopt once
    my @arg = qw( --gene_type_prefix mumble );
    getopt_with_args(@arg);
    is(getcfg('gene_type_prefix'), 'mumble', 'getopt flag visible');
    like(getcfg('url'), qr{http}, 'see hardwired default [client] url');
    is(getcfg('author'), undef, 'no default author'); # that happens in B:O:L:Client

    # getopt twice
    like((try { getopt_with_args(@arg) } catch {"ERR:$_"}),
         qr{already called}, 'do_getopt only once');

    return ();
}

sub makenew_tt {
    plan tests => 7;
    test_config('makenew_tt');
    getopt_with_args(qw( --gene_type_prefix BAR ));

    my $A = 'alice@example.com';
    is(getcfg('author'), undef, 'no author yet');
    putcfg(client => author => $A);
    like(wholecfg(), qr{\A# Config auto-created .*\n# Config auto-updated .*\n\[client\]\nauthor=\Q$A\E\n\z},
         'fresh config looks right');
    is(getcfg('author'), $A, 'author A set now');

    my $B = 'bob@example.org';
    putcfg(client => gene_type_prefix => 'FOO');
    putcfg(client => author => $B);
    is(getcfg('gene_type_prefix'), 'BAR', 'user config shadowed by getopt');
    is(getcfg('author'), $B, 'author B updated');

    test_config('makenew_tt');
    getopt_with_args();
    is(getcfg('gene_type_prefix'), 'FOO', 'user config unshadowed by reset');
    is(getcfg('author'), $B, 'author stays updated');

    return ();
}

sub async_edit_tt {
    plan tests => 13;

    my @warn;
    local $SIG{__WARN__} = sub { push @warn, "@_" };

    test_config('async_edit_nop');
    getopt_with_args();
    putcfg(client => author => 'alice');
    my $old = wholecfg();
    my $new = hack_config(qr{\n}, "\n\n", qr{=}, " = ");
    my $show;
    $show = 1 unless unlike($old, qr{ = |\n\n}, 'old is low-whitespace');
    $show = 1 unless like($new, qr{ = }, 'new has " = "');
    $show = 1 unless like($new, qr{\n\n}, 'new has "\n\n"');
    diag "---\n$old+++\n$new\n" if $show;
    is((try { putcfg(client => author => 'bob'); getcfg('author') }
        catch {"ERR:$_"}), 'bob', 'space-modified config is replaced');
    is(scalar @warn, 0, 'no warnings') or diag(@warn);

    @warn = ();
    test_config('async_edit_prod');
    getopt_with_args();
    putcfg(client => author => 'alice');
    is(getcfg('extra'), undef, 'no extra yet');
    hack_config(qr{\z}, "extra=more\n");

    like((try { putcfg(client => author => 'bob'); 'done' }
          catch {"ERR:$_"}),
         qr{File .* changed since},
         'line-added config rejects change');
    is(getcfg('author'), 'alice', 'bob not configured');
    is(scalar @warn, 1, 'no warnings') or diag(@warn);
    like((join "\n", @warn), qr{alice\nextra=more\n}, "warning with config text");

    @warn = ();
    test_config('async_edit_prod');
    getopt_with_args();
    is(getcfg('extra'), 'more', 'extra kept');
    is(getcfg('author'), 'alice', 'bob not saved');
    is(scalar @warn, 0, 'no warnings') or diag(@warn);

    return ();
}

sub hack_config {
    my @edit = @_;
    my $cfg = wholecfg();
    while (my ($match, $replace) = splice @edit, 0, 2) {
        my $changes = $cfg =~ s{$match}{$replace}mg;
        die "unchanged for s{$match}{$replace}mg" unless $changes;
    }
    write_file(Bio::Otter::Lace::Defaults::user_config_filename(),
               { atomic => 1 },
               $cfg);
    return $cfg;
}

sub multiwrite_tt {
    plan tests => 1;

    test_config('multiwrite_tt');
    getopt_with_args();

    foreach my $A (qw( Bob Fred Gina )) {
        putcfg(client => author => $A);
    }
    like(wholecfg(), qr{\A# Config auto-created .*\n# Config auto-updated .*\n\[client]\nauthor=Gina\n\z},
         'config auto-comments and one option');
    return ();
}

main();
