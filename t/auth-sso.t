#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use LWP::UserAgent;
use YAML 'Dump';

use Bio::Otter::Auth::SSO;


sub main {
    my @subt = qw( login_tt lockout_tt );
    plan tests => scalar @subt;
    foreach my $subt (@subt) {
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


sub login_tt {
    my @cred = grep { $_->[0] eq 'sso' } creds();
    if (!@cred) {
        my $fn = creds_fn();
        plan skip_all => "No credentials with type='sso' in $fn .  Please add a junk account.";
        return;
    }

    plan tests => 9;
    my $ua = get_ua();

    ### Valid login
    #
    is(scalar cookie_names($ua), 0, 'Jar is empty');

    my (undef, $user, $password) = @{ $cred[0] };
    my ($status, $failed, $detail) =
      Bio::Otter::Auth::SSO->login($ua, $user, $password);
    my @n = cookie_names($ua);

    is($failed, '', "Login OK (user=$user)")
      or diag Dump({ detail => $detail });
    like((join ',', @n), qr{(^|,)WTSISignOn($|,)}, 'Expected cookie present');
    is($status, '302 Found', 'Status redirect');

    ### Junk password login
    #
    $ua->cookie_jar->clear;
    ($status, $failed, $detail) =
      Bio::Otter::Auth::SSO->login($ua, $user, 'junketty-junk');
    @n = cookie_names($ua);

    like($failed, qr{^Login failed: (Please enter your login|Invalid account details)}, 'Junk login fail');
# qr{^Authentication as \Q$user\E failed: mumbly bumble},
    unlike((join ',', @n), qr{(^|,)WTSISignOn($|,)}, 'Expected cookie absent');
    is($status, '403 Forbidden', 'Status forbidden');

    ### Valid again, redirected
    #
    push @{ $ua->requests_redirectable }, 'POST';

    $ua->cookie_jar->clear;
    ($status, $failed, $detail) =
      Bio::Otter::Auth::SSO->login($ua, $user, $password);
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
          Bio::Otter::Auth::SSO->login($ua, 'locksmith', 'lost-my-key');
        last if $failed =~ /locked/;
        diag "Failed = $failed; $retry left.";
    }

    like($failed, qr{temporarily locked}, 'Lockout detected')
      or diag Dump({ detail => $detail });

    return;
}
