#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Try::Tiny;
use File::Temp 'tempdir';
use File::Path 'make_path';

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
    plan tests => 4;

    my $tmp = tempdir('BOSConfig.t.XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $vsn = Bio::Otter::Version->version;
    foreach my $file ("$vsn/otter_config", "$vsn/otter_styles.ini",
                      "users.txt", "species.dat") {
        mkfile("$tmp/asc_tt/$file");
        mkfile("$tmp/web_tt/data/otter/$file");
        mkfile("$tmp/priv_tt/main/$file");
        mkfile("$tmp/priv_tt/dev/$file");
    }

    foreach my $test (qw( asc_tt web_tt priv_tt )) {
        subtest $test => sub {
            return __PACKAGE__->$test("$tmp/$test");
        }
    }

  SKIP: {
        skip 1, 'not internal' unless -d '/nfs/anacode';
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
    delete @ENV{qw{ ANACODE_SERVER_CONFIG ANACODE_SERVER_DEVCONFIG DOCUMENT_ROOT REQUEST_URI SCRIPT_NAME }};
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

    # Access OK to (untouched) live config
    set_env();
    like(try_err { $BOSC->data_filename('databases.yaml') },
         qr{^/.*yaml$}, 'live dir mended');

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
    ok(unlink("$dir/users.txt"), # or any other we made
       'unlink one') or note "unlink: $!";
    like(try_err { $BOSC->data_dir },
         qr{^ERR:data_dir \S+_tt \(from \$ANACODE_SERVER_CONFIG\): lacks expected files \(users\.txt\)},
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


main();
