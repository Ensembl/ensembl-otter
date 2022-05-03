=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Otter::Auth::SSO;
use strict;
use warnings;

use URI::Escape qw{ uri_escape };
use HTTP::Request;
use LWP::UserAgent;


=head1 NAME

Bio::Otter::Auth::SSO - support for "legacy" login service

=head1 DESCRIPTION

Implements login (for client) and authentication (for server).

The caller must provide the relevant supporting objects:
L<LWP::UserAgent> on the client, L<SangerWeb> on the server.

=head1 CLASS METHODS

=head2 login($fetcher, $user, $pass)

Client side.  Given a valid username and password, obtain a cookie.

Returns C<($status, $failed, $detail)>.  $failed is a brief
explanation of the problem, or false on success.  $detail is the full
body of the reply.

Successful login modifies the cookie jar of $fetcher, to enable later
authenticated requests.

=cut

sub login {
    my ($called, $fetcher, $orig_user, $orig_password) = @_;

    # need to url-encode these
    my $user  = uri_escape($orig_user); # possibly not worth it...
    my $password = uri_escape($orig_password);  # definitely worth it!

    my $ua  = LWP::UserAgent->new();
    my $req = HTTP::Request->new;
    $req->method('GET');
    $req->uri("https://api.aai.ebi.ac.uk/auth");
    $req->content_type('application/json;charset=UTF-8');
    $req->authorization_basic($user, $orig_password);

    my $response = $ua->request($req);
    my $content = $response->decoded_content;
    my $failed;

    if ($response->is_success || $response->is_redirect) {
        $failed = '';
    } else {
        # log the detail - content may be large
        my $msg = sprintf("Authentication as %s failed: %s\n",
                          $orig_user, $response->status_line);
        if ($content =~ m{<title>Sanger Single Sign-on login}) {
            # Some common special cases
            if ($content =~ m{<P>(Invalid account details\. Please try again|Please enter your login and password to authenticate)</P>}i) {
                $msg = "Login failed: $1";
            } elsif ($content =~
                     m{The account <b>(.*)</b> has been temporarily locked}) {
                $msg = "Login failed and account $1 is now temporarily locked.";
                $msg .= "\nPlease wait $1 and try again, or contact Anacode for support"
                  if $content =~ m{Please try again in ((\d+ hours?)?,? \d+ minutes?)};
            } # else probably an entire HTML page
        }

        $failed = $msg;
    }
    return ($response->status_line, $failed, $content);
}


=head2 auth_user($sangerweb, $Access_obj)

Server side.  Given an existing L<SangerWeb> object containing the
client's authentication cookie, and the access control for users, set
flags for the user.

Returns a list of hash key => value pairs suitable for inserting into
L<Bio::Otter::Server::Support::Web> objects,

=over 4

=item _authenticated_user

The username, or C<undef> if none.

We know who it is, but maybe they should not be using our services.

=item _authorized_user

The username, or C<undef> if none.

User is allowed to use services, possibly with other restrictions.

=item _internal_user

True iff the user is authorised and "internal", i.e. a member of staff
or visiting worker.

=item _local_user

True iff the request originated inside the firewall.

=back

Note that this rolls authentication and authorisation into one lump.

=cut

sub auth_user {
    my ($called, $Access, $unauthorized_user) = @_;
    my %out = (_authenticated_user => undef,
               _authorized_user => undef,
               _internal_user => 0);

    $out{_local_user} = ($ENV{'HTTP_CLIENTREALM'} || '') =~ /sanger/
      ? 1 : 0;
    # ...from the HTTP header added by front end proxy


        my $auth_flag     = 0;
        my $internal_flag = 0;

        if ($unauthorized_user =~ /^[a-z0-9]+$/) {   # Internal users (simple user name)
            $auth_flag = 1;
            $internal_flag = 1;
        } elsif ($Access->user($unauthorized_user)) {  # Check configured users (email address)
            $auth_flag = 1;
        } # else not auth

        $out{_authenticated_user} = $unauthorized_user; # not used by B:O:SSS

        if ($auth_flag) {
            $out{'_authorized_user'} = $unauthorized_user;
            $out{'_internal_user'}   = $internal_flag;
        }
    

    die 'wantarray!' unless wantarray;
    return %out;
}


=head2 test_key()

Return the name of the key output by L<scripts/apache/test> which
exposes cookie interpretation.

=cut

sub test_key {
    return 'B:O:Auth::SSO';
}


=head2 cookie_name()

Return the name of the cookie used by this system.  This is present to
reduce magic strings in the automated test.

=cut

sub cookie_name {
    return 'WTSISignOn';
}


1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
