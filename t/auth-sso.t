#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use LWP::UserAgent;
use YAML qw( Dump Load );
use Try::Tiny;

use Bio::Otter::Server::Config;
use Bio::Otter::Lace::Defaults;
use File::Temp 'tempfile';

use Bio::Otter::Auth::SSO;
use Bio::Otter::Auth::Pagesmith;


our ($MODE, $CLASS);
sub main {
    my @sso = qw( login_tt auth_tt external_tt lockout_tt );
    my @ps  = qw( login_tt auth_tt external_tt );
    plan tests => @sso + @ps;

    $MODE = 'SSO';
    $CLASS = "Bio::Otter::Auth::$MODE";
    foreach my $subt (@sso) {
        subtest $subt => main->can($subt);
    }

    $MODE = 'Pagesmith';
    $CLASS = "Bio::Otter::Auth::$MODE";
    foreach my $subt (@ps) {
        subtest $subt => main->can($subt);
    }
}

main();


sub creds_fn {
    my $fn = $0;
    $fn =~ s{(^|/)[^/]+$}{$1.auth-credentials}
      or die "Can't make filename from $fn";
    return $fn;
}

sub creds {
    my $fn = creds_fn();
    if (!-f $fn) {
        open my $fh, '>', $fn
          or die "Can't create blank $fn: $!";
        print {$fh} "# Used by auth-*.t\n#\n# type user pass comment\n\n";
        close $fh;
        warn "Made empty $fn";
    }
    chmod 0600, $fn or die "Failed to make $fn file private: $!";

    open my $fh, '<', $fn
      or die "Reading $fn: $!";
    my @ln = grep { ! /^\s*(#|$)/ } <$fh>;
    chomp @ln;
    return map {[ split /\s+/, $_ ]} @ln;
}

sub cookie_names {
    my ($ua) = @_;
    my $jar = $ua->cookie_jar;
    my @n;
    $jar->scan(sub {
                   my ($version, $key, $val, $path, $domain, $port,
                       $path_spec, $secure, $expires, $discard, $hash) = @_;
                   push @n, $key;
                   return;
               });
    return @n;
}

sub get_ua {
    my $ua = LWP::UserAgent->new;
    $ua->env_proxy;
    $ua->cookie_jar({});

    return $ua;
}

sub get_interpretation {
    my ($client, $auth_class) = @_;

    my $txt = $client->http_response_content('GET', 'test');
    my $key = $auth_class->test_key;

    # scripts/apache/test emits YAML since e295bb7a 2012-06-28 v67
    my @data = Load($txt);

    die "Result does not include key '$key'" unless exists $data[0]->{$key};
    return ($data[0]->{$key}, $data[0]->{'B:O:Server::Config'});
}


sub auth_tt {
    my @cred = grep { $_->[0] eq "\L$MODE" } creds();

    # Find suitable user:pass
    my $users_hash = Bio::Otter::Server::Config->users_hash;
    my $users_fn_here = Bio::Otter::Server::Config->data_filename('users.txt');
    @cred = grep {
        my $u = $_->[1];
        (exists $users_hash->{ $u } && # authorised here, so should be on server
         $_->[1] =~ /\@/ && $_->[1] !~ /\@sanger/); # not internal
    } @cred;

    if (!@cred) {
        plan skip_all => "Need a type='\L$MODE\E' credential, listed in users_hash at $users_fn_here";
        return;
    }
    plan tests => 12;

    ### Obtain a standard client
    #
    # Do not trample caller's cookies!
    my ($fh, $fn) = tempfile('auth_tt.cookies.XXXXXX', TMPDIR => 1, CLEANUP => 1);
    local $ENV{'OTTERLACE_COOKIE_JAR'} = $fn;

    local @ARGV = ();
    Bio::Otter::Lace::Defaults::do_getopt();
    my $cl_safejar = Bio::Otter::Lace::Defaults::make_Client();

    # Do not pester for password
    $cl_safejar->password_prompt
      (sub { die "Test expected to be authorised\n".
               "  or Inside (possibly via env_proxy) ..?\n" });

    ### Check test info - logged out
    #
    my $ua = $cl_safejar->get_UserAgent;
    $ua->cookie_jar->clear;
    my ($info, $conf_there) = try {
        get_interpretation($cl_safejar, $CLASS);
    } catch { "ERR:$_" };

  SKIP: {
        unless (is(ref($info), 'HASH', 'Interpretation (logged out)')) {
            diag Dump({ interpretation => $info });
            skip "Can't get interpretation", 5;
        }

        my @i_key = sort keys %$info;
        my @want_key = qw( _authenticated_user _authorized_user _internal_user _local_user );
        is("@i_key", "@want_key", '  Keys');
        is($info->{_authenticated_user}, undef, '  Authenticated');
        is($info->{_authorized_user}, undef, '  Unauthorised');
        is($info->{_internal_user}, 0, '  Not internal');
        is($info->{_local_user}, 1, '  Local (must be - we are seeing test data)');
    }

    ### Log in (not via B:O:L:Client)
    #
    my (undef, $user, $password) = @{ $cred[0] };
    my ($status, $failed, $detail) =
      $CLASS->login($ua, $user, $password);
    is($failed, '', "Login OK (user=$user)");
    $ua->cookie_jar->save;

    ($info) = try {
        get_interpretation($cl_safejar, $CLASS);
    } catch { "ERR:$_" };

  SKIP: {
        unless (is(ref($info), 'HASH', "Interpretation (logged in)")) {
            diag Dump({ interpretation => $info });
            skip "Can't get interpretation", 4;
        }

        my $authen =
          is($info->{_authenticated_user}, $user, '  Authenticated')
            ? 'true' : 'false';

        is($info->{_authorized_user}, $user, '  Authorised')
          or diag("\nWhen listed in $users_fn_here (true),\n".
                  "and authenticated ($authen),\n".
                  "Could still be not authorised on server?  It reports config as\n".
                  Dump($conf_there));
        is($info->{_internal_user}, 0, '  Not internal'); # unix login password stored in local file == FAIL
        is($info->{_local_user}, 1, '  Local (must be - we are seeing test data)');
    }

    return;
}


sub login_tt {
    my @cred = grep { $_->[0] eq "\L$MODE" } creds();
    if (!@cred) {
        my $fn = creds_fn();
        plan skip_all => "No credentials with type='\L$MODE\E' in $fn .  Please add a junk account.";
        return;
    }

    plan tests => 9;
    my $ua = get_ua();

    ### Valid login
    #
    is(scalar cookie_names($ua), 0, 'Jar is empty');

    my (undef, $user, $password) = @{ $cred[0] };
    my ($status, $failed, $detail) =
      $CLASS->login($ua, $user, $password);
    my @n = cookie_names($ua);

    my $cookey = $CLASS->cookie_name;
    is($failed, '', "Login OK (user=$user)")
      or diag Dump({ detail => $detail });
    like((join ',', @n), qr{(^|,)$cookey($|,)}, 'Expected cookie present');
    is($status, '302 Found', 'Status redirect');

    ### Junk password login
    #
    $ua->cookie_jar->clear;
    ($status, $failed, $detail) =
      $CLASS->login($ua, $user, 'junketty-junk');
    @n = cookie_names($ua);

    like($failed, qr{^Login failed: (Please enter your login|Invalid account details)}, 'Junk login fail')
      or diag Dump({ detail => $detail });
# qr{^Authentication as \Q$user\E failed: mumbly bumble},
    unlike((join ',', @n), qr{(^|,)$cookey($|,)}, 'Expected cookie absent');
    is($status, '403 Forbidden', 'Status forbidden');

    ### Valid again, redirected
    #
    push @{ $ua->requests_redirectable }, 'POST';

    $ua->cookie_jar->clear;
    ($status, $failed, $detail) =
      $CLASS->login($ua, $user, $password);
    @n = cookie_names($ua);

    is($failed, '', "Login, redirected")
      or diag Dump({ detail => $detail });
    is($status, '200 OK', 'Status 200');

    return;
}


sub lockout_tt {
    plan tests => 1;

    my $ua = get_ua();

    ### Lockout test
    #
    my ($status, $failed, $detail);
    my $retry = 3;
    while ($retry --) {
        ($status, $failed, $detail) =
          $CLASS->login($ua, 'locksmith', 'lost-my-key');
        last if $failed =~ /locked/;
        diag "Failed = $failed; $retry left.";
    }

    like($failed, qr{temporarily locked}, 'Lockout detected')
      or diag Dump({ detail => $detail });

    return;
}


sub external_tt {
    plan tests => 1;
    my $ua = get_ua();

    local $TODO = "We have no external proxy, so cannot view Otter Server from 'Outside'";
    fail('try it from outside');

    return;
}
