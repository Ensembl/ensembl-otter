package Bio::Otter::Auth::Pagesmith;
use strict;
use warnings;

use URI::Escape qw{ uri_escape };
use HTTP::Request;
use XML::XPath;


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

    my $req = HTTP::Request->new;
    $req->uri('https://www.sanger.ac.uk/login');
    $req->method('GET');
    $req->header(Accept => 'application/xhtml+xml');
    my $form_resp = $fetcher->request($req);
    __redirect_once($fetcher, $req, $form_resp) if $form_resp->is_redirect;
    my $form = $form_resp->decoded_content;

    unless ($form_resp->is_success) {
        return ($form_resp->status_line,
                'Cannot attempt to log in - no login form',
                $form);
    }

    # We got the login form, now extract features (recipe from mw6)
    $form =~ s{^<\?xml.*dtd">}{};
    $form =~ s{&pound;|&raquo;}{X}g;

    my $xpath = XML::XPath->new(xml => $form);
    my $nodeset = $xpath->find('//*/form/@action');

    unless ($nodeset->isa('XML::XPath::NodeSet') &&
            $nodeset->size) {
        return ($form_resp->status_line,
                'Cannot attempt to log in - did not understand login form',
                $form);
    }

    my @node_txt = map { $_->toString } $nodeset->get_nodelist;
    my ($url, $formkey);
    foreach my $node (@node_txt) {
        last if
          ($url, $formkey) = $node =~ m{.*"(.*\/-(.{20,25}))"};
    }
    unless ($url =~ m{^https:}) {
        return ($form_resp->status_line,
                'Cannot attempt to log in - failed to extract login URL from form',
                join "\n", @node_txt);
    }

    # Do the login
    $req = HTTP::Request->new;
    $req->method('POST');
    $req->uri($url);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("__utf8=%C2%A3&action=next&next=Login&email=$user&p$formkey=$password");

    my $response = $fetcher->request($req);
    my $content = $response->decoded_content;
    $content = $response->as_string unless $content =~ /\S/;
    my $failed;

    if ($response->is_success) {
        $failed = '';
    } else {
        # log the detail - content may be large
        my $msg = sprintf("Authentication as %s failed: %s\n",
                          $orig_user, $response->status_line);
        # no special text to notice yet
        $failed = $msg;
    }
    return ($response->status_line, $failed, $content);
}

sub __redirect_once {
    my ($fetcher, $req, $resp) = @_;

    # follow one redirect (UA was not configured to do so)
    $req = HTTP::Request->new;
    $req->method('GET');
    $req->uri( $resp->header('Location') );
    $req->header(Accept => 'application/xhtml+xml');
    $resp = $fetcher->request;

    return $resp;
}


sub auth_user {
    my ($called, $sangerweb, $users_hash) = @_;
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
        } elsif ($users_hash->{$user}) {  # Check external users (email address)
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
