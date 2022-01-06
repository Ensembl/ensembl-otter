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

package Bio::Otter::Auth::Access;
use strict;
use warnings;
use Try::Tiny;
use Carp;
use Scalar::Util 'weaken';
use Crypt::JWT qw(decode_jwt);

use Bio::Otter::Auth::DsList;
use Bio::Otter::Auth::UserGroup;
use Bio::Otter::Auth::User;

my $pem_key_string = <<'EOF';
-----BEGIN CERTIFICATE-----
MIIDYzCCAkugAwIBAgIELs3IYzANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJV
SzEQMA4GA1UECBMHRW5nbGFuZDESMBAGA1UEBxMJQ2FtYnJpZGdlMREwDwYDVQQK
EwhFTUJMLUVCSTEMMAoGA1UECxMDVFNDMQwwCgYDVQQDEwNBQVAwHhcNMTcxMDI2
MTQxNjQ1WhcNMTgwMTI0MTQxNjQ1WjBiMQswCQYDVQQGEwJVSzEQMA4GA1UECBMH
RW5nbGFuZDESMBAGA1UEBxMJQ2FtYnJpZGdlMREwDwYDVQQKEwhFTUJMLUVCSTEM
MAoGA1UECxMDVFNDMQwwCgYDVQQDEwNBQVAwggEiMA0GCSqGSIb3DQEBAQUAA4IB
DwAwggEKAoIBAQCJ5UQw0luRSZSBXAhAIooF0UFQCpSE0zyE81mAf51uOB18hkQK
moIfHycAZttBIkfX/ZnERmtkeEUypKy0lVNDcFZdAFRbwFCWjuRPGvWPylqRLmhj
WhUPfX3A0wHHoytVq+0yeaQTs1AhGmW3HJfw40qdtPq8K1ZSs+tbPfTgZusnPp50
o9JR/FJvB7ssVagqS0DiDwjaiMEWBUy0SfqRJyb12tX8wtwbYmS7BaHmB1fYlXqq
yoFTCMZvdGcCFtou2F10sfoKwGw/nV67EpViSDQ1REa3MISimzUtEg411k5+yUO1
7qABlzw9P31dL1L44CwrSp3jM8u/2LGwI8iRAgMBAAGjITAfMB0GA1UdDgQWBBST
2B50ZXlpshYwKHl1ugR1IdhGgDANBgkqhkiG9w0BAQsFAAOCAQEAbL+HaphJChCL
Zuft6RT3sQONx9i7bBnoz15i3I/Wo8er6ZgSuV9F5OGafV8qKqIoVycTAO5Dj5k2
wmvtdIJM0Pf0JB1IeJTnggn61Nkuoha4DuwRbEmUuujH6kuOMXyC555ZknK7ITTB
/kM3ZahmRzwvv3BzZpZ6t87M/XEWD4Vo7O8W7OF8sYKrUnGJ6/amgxme6WwYaA2g
kW1jCSBntkmh4hzRw7RKG2At4YRpUbF7wHEYmch1w5Jsna9lSrgdiNVBUeA9PRXc
Dnof5x7tPVGPQcwtA7KdEJe3dV8qxZ5mJNZt//yUgDrB9da7yRjtAR7E5FmBSnuC
FGsK9CPCSA==
-----END CERTIFICATE-----
EOF

=head1 NAME

Bio::Otter::Auth::Access - authorisation for authors' dataset access

=head1 SYNOPSIS

 # New style.
 my $acc = Bio::Otter::Server::Config->Access;
 my $user = $acc->user($email) or die "User not authorised";
 my $ds = $user->write_dataset($dataset_name)
   or die "User not authorised on that dataset";

=head1 DESCRIPTION

Class to collect all access control for users to datasets.

=head2 Overview

There is normally just one Access object.  Objects lower in the tree
hold a reference back to it to reach species info.  This is weakened,
so something must keep hold of the Access object.
L<Bio::Otter::Server::Config/Access> does this for normal use.

It holds

=over 4

=item - a L<Bio::Otter::SpeciesDat>

So dataset names can be checked.

=item - the C<species_groups>

To provide shortcuts to many datasets.

=item - the C<user_groups>

These are kept private to the object, because the groupings are for
brevity of configuration and not intended for API access.

=item - direct links to the user objects, in a flattened hash

User objects hold weak references to their user_group(s).

=back

L<Bio::Otter::Auth::DsList> are used to hold lists of datasets, for
the species groups and the access lists of users and user groups.
They get mashed together in combination where they are used.


=head1 METHODS

Construct-only, with read-only attributes.

=cut


sub new {
    my ($pkg, $hashref, $species_dat) = @_;
    my $self = { _species_dat => $species_dat,
                 _input => $hashref };
    bless $self, $pkg;

    local $self->{'_ptr'} = 'begin'; # where we are up to, with parsing
    try {
        $self->_check_species_groups;
        $self->_flatten_users;
        $self->_alias_map;      # causes map to be built
    } catch {
        my $err = $_;
        $err =~ s{\.?\s*\Z}{, under $$self{_ptr}};
        croak $err;
    };

    return $self;
}


=head2 species_dat()

The object carries its own ref to a L<Bio::Otter::SpeciesDat>
which usually matches B<Bio::Otter::Server::Config/SpeciesDat>.

This has not had access control applied and should not be used outside
the C<Bio::Otter::Auth::*> classes.

=cut

sub species_dat {
    my ($self) = @_;
    return $self->{'_species_dat'};
}

sub _input_optional {
    my ($self, $key) = @_;
    $self->{'_ptr'} = $key;
    return $self->{'_input'}->{$key};
}

sub _input {
    my ($self, $key) = @_;
    return $self->_input_optional($key) || die "Key $key not found in input";
}

sub species_groups {
    my ($self) = @_;
    return $self->{'_species_groups'}
      ||= $self->_build_species_groups($self->_input('species_groups'));
}


=head2 user($email)

This is the main interface to use on the object.

Return an authorised L<Bio::Otter::Auth::User>, or undef if not found.

The search key is C<lc($email)> but that need not concern the caller.
The resulting C<<$user->email>> case is preserved from the
configuration file.

=cut

sub user {
    my ($self, $email) = @_;
    return $self->all_users->{lc($email)};
}

sub _build_species_groups {
    my ($self, $sp_grps) = @_;
    my %out;
    while (my ($name, $sgroup) = each %$sp_grps) {
        $self->{'_ptr'} = "species_groups/$name";
        $out{$name} = Bio::Otter::Auth::DsList->new($self, $sgroup);
    }
    return \%out;
}

sub _check_species_groups {
    my ($self) = @_;
    while (my ($name, $dslist) = each %{ $self->species_groups }) {
        $self->{'_ptr'} = "species_groups/$name";
        my @ds = $dslist->datasets;
    }
    return;
}

sub _user_groups {
    my ($self) = @_;
    return $self->{'_user_groups'}
      ||= $self->_build_user_groups($self->_input('user_groups'));
}

sub _build_user_groups {
    my ($self, $u_grps) = @_;
    my %out;
    while (my ($name, $ugroup) = each %$u_grps) {
        $self->{'_ptr'} = "user_groups/$name";
        $out{$name} = Bio::Otter::Auth::UserGroup->new($self, $ugroup);
    }
    return \%out;
}


=head2 all_users()

Return the hashref of C<{ $email => $user_object }>.

This is intended for code testing, not production use.  It has the
weakness that it may not include all possible users, due to
the fact that it doesn't ask databases for lists of authors.

=cut

sub all_users {
    my ($self) = @_;
    return $self->{'_users'};
}


sub _flatten_users {
    my ($self) = @_;
    my %out;
    while (my ($name, $ugroup) = each %{ $self->_user_groups }) {
        $self->{'_ptr'} = "user_groups/$name";
        foreach my $u ($ugroup->users) {
            my $e = $u->email;
            die "Duplicate user $e" if $out{lc($e)}; # see $u->in_group comment
            $out{lc($e)} = $u;
        }
    }
    $self->{'_users'} = \%out;
    return;
}


=head2 user_by_alias($provider, $identifier)

This translates externally authenticated identifiers into Otter users.
$provider and $identifier are case-insensitive.

Return an authorised L<Bio::Otter::Auth::User>, or undef if not found.

=cut

sub user_by_alias {
    my ($self, $provider, $identifier) = @_;
    my $email = $self->_alias_map->{lc($provider)}->{lc($identifier)};
    return $self->user($email) if $email;

    return unless lc($provider) eq 'google';
    return $self->_sanger_google_alias($identifier);
}

# As a special case, internal users are assumed to have a google account
# with the same email address as their official sanger address.
#
sub _sanger_google_alias {
    my ($self, $identifier) = @_;

    my ($uname) = $identifier =~ /
      ^
      ([a-z0-9]+)      # simple user name
      \@sanger\.ac\.uk  # sanger mail
      $
    /ix;               # case-insensitive

    return unless $uname;
    return $self->user($uname);
}

sub _alias_map {
    my ($self) = @_;
    return $self->{'_alias_map'} ||= $self->_build_alias_map;
}

sub _build_alias_map {
    my ($self) = @_;

    my $u_aliases = $self->_input_optional('user_aliases');
    return {} unless $u_aliases;

    my %by_provider;
    while (my ($name, $alias_hash) = each %{ $u_aliases }) {
        $self->{'_ptr'} = "user_aliases/$name";
        die "user_alias user '$name' not found in user_groups" unless $self->user($name);
        while (my ($provider, $alias) = each %{ $alias_hash }) {
            die "Duplicate alias '$provider/$alias' for '$name'" if $by_provider{lc($provider)}->{lc($alias)};
            $by_provider{lc($provider)}->{lc($alias)} = $name;
        }
    }
    return \%by_provider;
}

sub _jwt_verify {
    my($self, $token) = @_;

    my $data = decode_jwt(token=>$token, key=>Crypt::PK::RSA->new(\$pem_key_string));
    return $data;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
