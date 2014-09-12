package Bio::Otter::Auth::Pagesmith;
use strict;
use warnings;

use URI::Escape qw{ uri_escape };
use HTTP::Request;


=head1 NAME

Bio::Otter::Auth::Pagesmith - support for "new (2012)" login service

=head1 DESCRIPTION

Implements login (for client) and authentication (for server).
(Authentication is broken.)

The caller must provide the relevant supporting objects:
L<LWP::UserAgent> on the client, L<SangerWeb> on the server.

=head1 CLASS METHODS

=head2 login($fetcher, $user, $pass)

Client side.  Given a valid username and password, obtain a cookie.

Returns C<($status, $failed, $detail)>.  $failed is a brief
explanation of the problem, or false on success.  $detail is the full
body of the reply, or other long debug text.

Successful login modifies the cookie jar of $fetcher, to enable later
authenticated requests.

=begin implementation_notes

Adapted from mw6 in <86DD6992-8982-4351-9E54-F19D471C953D@sanger.ac.uk>

  curl -s -D header.txt -L https://www.sanger.ac.uk/login -H "Accept:application/xhtml+xml" | sed -e 's/^<?xml.*dtd">//;s/&pound;\|&raquo;/X/' | xpath -p '//*/form/@action' 2>/dev/null | perl -pe 's/.*"(.*\/-(.{20,25}))"/curl -L $1 -c cookie.txt --data \"__utf8=%C2%A3&action=next&next=Login&email=\$user&p$2=\$password\"\n/'

=>
 curl -D header.txt -L https://www.sanger.ac.uk/form/-BjMWm4PyS1it_MBDZqkHkQ -c cookie.txt --data "__utf8=%C2%A3&action=next&next=Login&email=$user&pBjMWm4PyS1it_MBDZqkHkQ=$password"

That was with /software/perl-5.12.2/bin/xpath
/usr/bin/xpath might need -e instead of -p ?

=end implementation_notes

=cut

sub login {
    my ($called, $fetcher, $orig_user, $password) = @_;

    # need to url-encode these
    my $user  = uri_escape($orig_user); # possibly not worth it...
    $password = uri_escape($password);  # definitely worth it!

    my $init_uri = 'https://www.sanger.ac.uk/about/';
    # url needs to exist, but is irrelevant

    my $req = HTTP::Request->new;
    $req->uri('https://www.sanger.ac.uk/login');
    $req->method('GET');
    $req->header(Referer => $init_uri);
    my $form_resp = $fetcher->simple_request($req);
    my $form_dbg = $form_resp->as_string; # no secrets in these headers

    unless ($form_resp->is_redirect) {
        return ($form_resp->status_line,
                'Cannot attempt to log in - no login redirect',
                $form_dbg);
    }

    my ($formurl, $formkey) = $form_resp->header('Location')
      # e.g. https://www.sanger.ac.uk/form/-uqfpBomhQB2YxQ8HyUC9Rg
      =~ m{^(https:.*/-(.{20,25}))$};
    unless ($formkey) {
        return ($form_resp->status_line,
                'Cannot attempt to log in - failed to extract login URL from form',
                $form_dbg);
    }
    $formkey =~ s/-/_/g; # we get '-' in 33% of formurl; not valid in formkey
    $form_dbg .= "formurl=$formurl\nformkey=$formkey\n";

    # Do the login
    $req = HTTP::Request->new;
    $req->method('POST');
    $req->uri($formurl);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("__utf8=%C2%A3&action=next&next=Login&email=$user&p$formkey=$password");

    my $response = $fetcher->simple_request($req);
    my $content = $response->decoded_content;
#    $content = $response->as_string unless $content =~ /\S/; # could leak Set-Cookie: to 0644 logfile
    $content .= "\nInputs,\n$form_dbg";
    my $failed;

    my $redir;
    $redir = $response->header('Location') if $response->is_redirect;

    my $set_cookie = join "\n",
      map { $response->header($_) } qw( Set-Cookie Set-Cookie2 );
    my $want_cookie = $called->cookie_name;

    if ($redir eq $init_uri && $set_cookie =~ m{^$want_cookie=}mi) {
        # Success!
        #
        # Indications
        #  1) redirect is back to a www.sanger.ac.uk page containing
        #     <div id="user">$USER_NAME logged in <a href="/action/logout"><img id="logout" src="/core/gfx/blank.gif" alt="Logout" ></a></div>
        #  2) "Set-Cookie: Pagesmith_User=..." header
        $failed = '';

    } elsif ($redir eq $formurl && $set_cookie !~ m{$want_cookie}i) {
        # Fail!
        #
        # Indications
        #  1) redirect is back to (the same?) login form, containing
        #     <div id="user"><a href="/login"><img id="login" src="/core/gfx/blank.gif" alt="Login" /></a></div>
        #  2) no Set-Cookie: header

        $failed = 'Login failed: Invalid account details';
        # We must assume something like this - message chosen to match
        # old system.

    } else {
        # Indeterminate.  Follow it for the debug log.  Then if we
        # have a cookie, some later request might seem valid..?
        $failed = sprintf("Authentication as %s failed: Indeterminate response '%s'\n",
                          $orig_user, $response->status_line);

        if ($response->is_redirect) {
            # most likely - for pass or fail
            my $followed = __redirect_once($fetcher, $req, $response);
            $content .= "\n--- redirected to $redir ---\n".
              $followed->decoded_content;
        }
    }

    return ($response->status_line, $failed, $content);
}

sub __redirect_once {
    my ($fetcher, $req, $resp) = @_;

    # follow one redirect (we don't want auto-follow because the
    # redirects are significant)
    $req = HTTP::Request->new;
    $req->method('GET');
    $req->uri( $resp->header('Location') );
    $resp = $fetcher->simple_request($req);

    return $resp;
}


sub auth_user {
    my ($called, $sangerweb, $Access) = @_;
    my %out = (_authenticated_user => undef,
               _authorized_user => undef,
               _internal_user => 0);

    $out{_local_user} = ($ENV{'HTTP_CLIENTREALM'} =~ /sanger/ ? 1 : 0);
    # ...from the HTTP header added by front end proxy

    my $user; # now what?

    if ($user) {
        my $auth_flag     = 0;
        my $internal_flag = 0;

        if ($user =~ /^[a-z0-9]+\@sanger\.ac\.uk$/) {   # Internal users
            $auth_flag = 1;
            $internal_flag = 1;
        } elsif ($Access->user($user)) {  # Check configured users (email address)
            $auth_flag = 1;
        } # else not auth

        $out{_authenticated_user} = $user; # not used by B:O:SSS

        if ($auth_flag) {
            $out{'_authorized_user'} = $user;
            $out{'_internal_user'}   = $internal_flag;
        }
    }

    die 'wantarray!' unless wantarray;
    return %out;
}


=head2 test_key()

Return the name of the key output by L<scripts/apache/test> which
exposes cookie interpretation.

=cut

sub test_key {
    return 'B:O:Auth::Pagesmith';
}


=head2 cookie_name()

Return the name of the cookie used by this system.  This is present to
reduce magic strings in the automated test.

=cut

sub cookie_name {
    return 'Pagesmith_User';
}


1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
