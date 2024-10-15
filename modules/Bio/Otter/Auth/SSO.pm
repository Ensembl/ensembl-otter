=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

Client side. Used to obtain a JWT from an auth server.
Now it returns a dummy string.

=cut

sub login {
    my ($called, $fetcher, $orig_user, $orig_password) = @_;

    my $content = "NoAuth";
    my $failed = '';
    return ("200 OK", $failed, $content);
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

=cut

sub auth_user {
    my ($called, $Access, $unauthorized_user) = @_;
    my %out = (_authenticated_user => undef,
               _authorized_user => undef,
               _internal_user => 0);

    $out{_local_user} = 1;
    $out{_authenticated_user} = $unauthorized_user; # not used by B:O:SSS
    $out{'_authorized_user'} = $unauthorized_user;
    $out{'_internal_user'}   = 1;

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
