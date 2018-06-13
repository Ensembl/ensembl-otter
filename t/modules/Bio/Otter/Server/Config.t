#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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
use Try::Tiny;
use File::Temp 'tempdir';
use File::Path 'make_path';
use YAML::Any;

use Test::Otter 'try_err';

use Bio::Otter::Version;


# Check we can use BOSC to...
#
use Bio::Otter::Server::Config;
#
#   find config given explicitly or on webserver
#   (the default is just for convenience, doesn't work offsite)
#
#   get meaningful error messages on breakage


sub main {
    plan tests => 6;
    umask 022;

    my $tmp = tempdir('BOSConfig.t.XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $vsn = Bio::Otter::Version->version;
    foreach my $test ( qw( asc_tt
                           web_tt/data/otter
                           priv_tt/main            priv_tt/dev
                           with_local_tt/no_local  with_local_tt/local
                           yaml_tt
                         ) )
    {
        my $dir = "$tmp/$test";
        foreach my $file ("$vsn/otter_config", "$vsn/otter_styles.ini",
                          "access.yaml", "species.dat", "databases.yaml") {
            mkfile("$dir/$file");
        }
    }
    foreach my $test ( qw( with_local_tt/local
                           yaml_tt ) )
    {
        mkfile("$tmp/$test/.local/databases.yaml");
        mkfile("$tmp/$test/.local/databases.test.yaml");
    }

    foreach my $test (qw( asc_tt web_tt priv_tt with_local_tt yaml_tt )) {
        subtest $test => sub {
            return __PACKAGE__->$test("$tmp/$test");
        }
    }

  SKIP: {
        skip 'not internal', 1 unless -d '/nfs/anacode';
        subtest fallback_tt => \&fallback_tt;
    }

    return;
}

sub mkfile {
    my ($fn, $txt) = @_;
    $txt = "junk\n" unless defined $txt;
    my ($dir) = $fn =~ m{^(.*)/};
    make_path $dir;
    open my $fh, '>', $fn or die "mkfile $fn: $!";
    print {$fh} $txt;
    return;
}

# Set specified vars, clear other relevant ones
sub set_env { ## no critic (Foo)
    my (%kv) = @_;
    delete @ENV{qw{ ANACODE_SERVER_CONFIG
                    ANACODE_SERVER_DEVCONFIG
                    DOCUMENT_ROOT
                    OTTER_WEB_STREAM
                    REQUEST_URI
                    SCRIPT_NAME }};
    while (my ($k, $v) = each %kv) {
        $ENV{$k} = $v;
    }
    return;
}


sub priv_tt {
    my ($pkg, $dir) = @_;
    my $BOSC = 'Bio::Otter::Server::Config';
    plan tests => 4;

    ## no critic (ValuesAndExpressions::ProhibitLeadingZeros) here be octal perms
    # Emulate Apache data/otter/ being public
    set_env(ANACODE_SERVER_CONFIG => "$dir/main");
    __chmod(0755, "$dir/main");
    like(try_err { $BOSC->data_filename('databases.yaml') },
         qr{^ERR:.*Insufficient privacy \(found mode 0755, want 0750\) on .*priv_tt/main },
         'reject public data_dir');
    __chmod(0750, "$dir/main");

    # Emulate ~/.otter/server-config/ being public
    set_env(ANACODE_SERVER_CONFIG => "$dir/main",
            ANACODE_SERVER_DEVCONFIG => "$dir/dev");
    __chmod(0705, "$dir/dev");
    like(try_err { $BOSC->data_filename('databases.yaml') },
         qr{^ERR:.*Insufficient privacy \(found mode 0705, want 0700\) on .*priv_tt/dev },
         'reject public _dev_config');

    # Access OK to test config
    __chmod(0750, "$dir/dev");
    like(try_err { $BOSC->data_filename('databases.yaml') },
         qr{^/.*/priv_tt/dev/databases\.yaml$}, 'test dirs mended');

  SKIP: {
    skip 'not internal', 1 unless -d '/nfs/anacode';

    # Access OK to (untouched) live config
    set_env();
    like(try_err { $BOSC->data_filename('databases.yaml') },
         qr{^/.*yaml$}, 'live dir mended');
    }
    
    return;
}

sub __chmod {
    my ($perm, $fn) = @_;
    chmod $perm, $fn
      or die sprintf("chmod 0%o %s: %s", $perm, $fn, $!);
    return;
}

sub asc_tt {
    my ($pkg, $dir) = @_;
    my $BOSC = 'Bio::Otter::Server::Config';
    plan tests => 4;

    # broken
    set_env(ANACODE_SERVER_CONFIG => "$dir/absent");
    like(try_err { $BOSC->data_dir },
         qr{^ERR:data_dir \S+_tt/absent \(from \$ANACODE_SERVER_CONFIG\): not found },
         'absent');

    # like a developer
    set_env(ANACODE_SERVER_CONFIG => $dir);
    like(try_err { $BOSC->data_dir }, qr{^/\S+_tt/?$}, 'find direct');

    # broken
    ok(unlink("$dir/access.yaml"), # or any other we made
       'unlink one') or note "unlink: $!";
    like(try_err { $BOSC->data_dir },
         qr{^ERR:data_dir \S+_tt \(from \$ANACODE_SERVER_CONFIG\): lacks expected files \(access\.yaml\)},
         'find incomplete');

    return;
}


sub web_tt {
    my ($pkg, $dir) = @_;
    my $BOSC = 'Bio::Otter::Server::Config';
    plan tests => 4;

    # broken
    set_env(DOCUMENT_ROOT => "$dir/absent/junk");
    like(try_err { $BOSC->data_dir },
         qr{^ERR:data_dir \S+_tt/absent/data/otter \(from \$DOCUMENT_ROOT near root '\S+_tt/absent/junk'\): not found },
         'absent');

    # like a webserver
    set_env(DOCUMENT_ROOT => "$dir/htdocs"); # htdocs/ does not exist
    my $dd = try_err { $BOSC->data_dir };
    like($dd, qr{^/\S+_tt/data/otter/?$}, 'find via htdocs');

    # overspecified
    set_env(DOCUMENT_ROOT => "$dir/htdocs",
            ANACODE_SERVER_CONFIG => "$dir/irrelevant");
    my @warn;
    my $dd_overspec = try_err {
        local $SIG{__WARN__} = sub { my ($msg) = @_; push @warn, $msg };
        return $BOSC->data_dir;
    };
    is($dd_overspec, $dd, 'again with ANACODE_SERVER_CONFIG set');
    like($warn[0] || '(no first warning)',
         qr{\$ANACODE_SERVER_CONFIG ignored because \$DOCUMENT_ROOT was set},
         'precedence warning');

    return;
}


# Can't test this Outside
sub fallback_tt {
    my $BOSC = 'Bio::Otter::Server::Config';
    plan tests => 1;

    set_env();
    my $dd = try_err { $BOSC->data_dir };
    like($dd, qr{^/\S+/data/otter/?$}, 'fallback default')
      && note $dd;

    return;
}


sub with_local_tt {
    my ($pkg, $dir) = @_;
    my $BOSC = 'Bio::Otter::Server::Config';
    plan tests => 8;

    # Not there
    set_env(ANACODE_SERVER_CONFIG => "$dir/absent");
    like(try_err { $BOSC->data_filenames_with_local('databases.yaml') },
         qr{^ERR:data_dir \S+_tt/absent \(from \$ANACODE_SERVER_CONFIG\): not found },
         'absent');

    # No .local dir
    set_env(ANACODE_SERVER_CONFIG => "$dir/no_local");
    __chmod(0750, "$dir/no_local");
    __chmod(0600, "$dir/no_local/databases.yaml");
    my @paths = $BOSC->data_filenames_with_local('databases.yaml');
    is_deeply(\@paths, [ "$dir/no_local/databases.yaml" ], 'no local');

    # Bad privacy on .local
    set_env(ANACODE_SERVER_CONFIG => "$dir/local");
    __chmod(0750, "$dir/local");
    __chmod(0600, "$dir/local/databases.yaml");
    like(try_err { $BOSC->data_filenames_with_local('databases.yaml') },
         qr{^ERR:Insufficient privacy \(found mode 0755, want 0750\) on .*local/.local},
         'privacy on .local dir');

    __chmod(0700, "$dir/local/.local");
  SKIP: {
    skip 'be stricter later, but not now', 1;
    like(try_err { $BOSC->data_filenames_with_local('databases.yaml') },
         qr{^ERR:Insufficient privacy \(found mode 0644, want 0640\) on .*local/.local/databases.yaml},
         'privacy on .local/databases.yaml');
    }

    # .local, stream not set
    __chmod(0600, "$dir/local/.local/databases.yaml");
    @paths = $BOSC->data_filenames_with_local('databases.yaml');
    is_deeply(\@paths,
              [ "$dir/local/databases.yaml",
                "$dir/local/.local/databases.yaml",
              ],
              'local, no stream');

    set_env(ANACODE_SERVER_CONFIG => "$dir/local", OTTER_WEB_STREAM => 'test');
  SKIP: {
    skip 'be stricter later, but not now', 1;
    # Bad privacy on .local/databases.test.yaml
    like(try_err { $BOSC->data_filenames_with_local('databases.yaml') },
         qr{^ERR:Insufficient privacy \(found mode 0644, want 0640\) on .*local/.local/databases.test.yaml},
         'privacy on .local/databases.test.yaml');
    }

    # .local, stream not set
    __chmod(0600, "$dir/local/.local/databases.test.yaml");
    @paths = $BOSC->data_filenames_with_local('databases.yaml');
    is_deeply(\@paths,
              [ "$dir/local/databases.yaml",
                "$dir/local/.local/databases.yaml",
                "$dir/local/.local/databases.test.yaml",
              ],
              'local, with stream');

    # .local, stream only
    unlink("$dir/local/.local/databases.yaml");
    @paths = $BOSC->data_filenames_with_local('databases.yaml');
    is_deeply(\@paths,
              [ "$dir/local/databases.yaml",
                "$dir/local/.local/databases.test.yaml",
              ],
              'local, stream only');

    return;
}

sub yaml_tt {
    my ($pkg, $dir) = @_;
    my $BOSC = 'Bio::Otter::Server::Config';
    plan tests => 3;

    set_env(ANACODE_SERVER_CONFIG => "$dir");
    __chmod(0750, "$dir");
    __chmod(0750, "$dir/.local");
    __chmod(0600, "$dir/databases.yaml");
    __chmod(0600, "$dir/.local/databases.yaml");
    __chmod(0600, "$dir/.local/databases.test.yaml");

    like(try_err { $BOSC->_get_yaml('databases.yaml') },
         qr{^ERR:YAML Error},
         'Bad YAML');

    __write_yaml($dir);

    my %exp = (
        a => 1,
        b => {
            c => 2,
            d => [3, 4],
            e => 'boo',
        },
        f => 'hoo',
        LOCAL => { 'colour' => 'Red' },
        );

    is_deeply($BOSC->_get_yaml('databases.yaml'), \%exp, 'no stream');

    set_env(ANACODE_SERVER_CONFIG => "$dir", OTTER_WEB_STREAM => 'test');
    $exp{b}->{e} = 'changed';
    @exp{qw( g h j k )} = ( 42, $dir, 'Red', 'test' );
    is_deeply($BOSC->_get_yaml('databases.yaml'), \%exp, 'with stream');

    return;
}

sub __write_yaml {
    my ($dir) = @_;

    YAML::DumpFile("$dir/databases.yaml", {
        a => 1,
        b => {
            c => 2,
            d => [3, 4],
        },
                   });
    YAML::DumpFile("$dir/.local/databases.yaml", {
        LOCAL => { 'colour' => 'Red' },
        b => { e => 'boo' },
        f => 'hoo',
                   });
    YAML::DumpFile("$dir/.local/databases.test.yaml", {
        b => { e => 'changed' },
        g => 42,
        h => '__ENV(ANACODE_SERVER_CONFIG)__',
        j => '__LOCAL(colour)__',
        k => '__STREAM__',
                   });
    return;
}

main();
