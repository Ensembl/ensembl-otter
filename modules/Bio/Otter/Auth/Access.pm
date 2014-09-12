package Bio::Otter::Auth::Access;
use strict;
use warnings;
use Try::Tiny;
use Carp;
use Scalar::Util 'weaken';

use Bio::Otter::Auth::DsList;
use Bio::Otter::Auth::UserGroup;
use Bio::Otter::Auth::User;


=head1 NAME

Bio::Otter::Auth::Access - authorisation for authors' dataset access

=head1 SYNOPSIS

 # New style.  NB. there is no implicit access granted to staff.
 my $acc = Bio::Otter::Server::Config->Access;
 my $user = $acc->user($email) or die "User not authorised";
 my $ds = $user->write_dataset($dataset_name)
   or die "User not authorised on that dataset";

 # Old style / legacy
 my $users_txt = Bio::Otter::Server::Config->users_hash;
 my $user = $users_txt->{lc($email)}; # nb. explicit downcasing
 my $authorised = _allow_implicit_access($email, $dataset_name)
   or try { $user->{$dataset_name} };


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

    local $self->{_ptr} = 'begin'; # where we are up to, with parsing
    try {
        $self->_check_species_groups;
        $self->_flatten_users;
    } catch {
        my $err = $_;
        $err =~ s{\.?\s*\Z}{, under $$self{_ptr}};
        croak $err;
    };

    return $self;
}

sub species_dat {
    my ($self) = @_;
    return $self->{_species_dat};
}

sub _input {
    my ($self, $key) = @_;
    $self->{_ptr} = $key;
    return $self->{_input}->{$key} or die "Key $key not found in input";
}

sub species_groups {
    my ($self) = @_;
    return $self->{_species_groups}
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
        $self->{_ptr} = "species_groups/$name";
        $out{$name} = Bio::Otter::Auth::DsList->new($self, $sgroup);
    }
    return \%out;
}

sub _check_species_groups {
    my ($self) = @_;
    while (my ($name, $dslist) = each %{ $self->species_groups }) {
        $self->{_ptr} = "species_groups/$name";
        my @ds = $dslist->datasets;
    }
    return;
}

sub _user_groups {
    my ($self) = @_;
    return $self->{_user_groups}
      ||= $self->_build_user_groups($self->_input('user_groups'));
}

sub _build_user_groups {
    my ($self, $u_grps) = @_;
    my %out;
    while (my ($name, $ugroup) = each %$u_grps) {
        $self->{_ptr} = "user_groups/$name";
        $out{$name} = Bio::Otter::Auth::UserGroup->new($self, $ugroup);
    }
    return \%out;
}


=head2 all_users()

Return the hashref of C<{ $email => $user_object }>.

This is intended for code testing, not production use.  It has the
weakness that it may not include all possible users, due to
L</legacy_access> and the fact that it doesn't ask databases for lists
of authors.

=cut

sub all_users {
    my ($self) = @_;
    return $self->{_users};
}


sub _flatten_users {
    my ($self) = @_;
    my %out;
    while (my ($name, $ugroup) = each %{ $self->_user_groups }) {
        $self->{_ptr} = "user_groups/$name";
        foreach my $u ($ugroup->users) {
            my $e = $u->email;
            die "Duplicate user $e" if $out{lc($e)}; # see $u->in_group comment
            $out{lc($e)} = $u;
        }
    }
    $self->{_users} = \%out;
    return;
}


=head2 legacy_access($email)

Given an email address, modify the objects state to grant legacy
access as under F<users.txt>; but read only.

If the user was already listed explicitly, nothing happens.  This
could result in reduced access.

=cut

sub legacy_access {
    my ($self, $email) = @_;

    # XXX:DUP belongs to Bio::Otter::Auth::SSO::auth_user
    my $internal_flag = ($email =~ m{^[a-z0-9]+$});

    if ($internal_flag && !$self->user($email)) {
        my %G = (comment => "Made by $self->legacy_access for $email",
                 read => [ ':main' ]);
        my $G = Bio::Otter::Auth::UserGroup->new($self, \%G);
        my $U = Bio::Otter::Auth::User->new($self, $email);
        $U->in_group($G);

        $self->_user_groups->{legacy_access} = $G;
        $self->all_users->{$email} = $U;
    }

    return;
}

=head2 legacy_users_hash(@opt)

Return a reconstruction of the C<users_hash()> made from the old
F<users.txt> .  This ignores users' read-only datasets.

=cut

sub legacy_users_hash {
    my ($self, @opt) = @_;
    my $preserve_case = ("@opt" eq 'samecase'); # for testing

    my %main; # names of the unrestricted datasets
    {
        my @name = Bio::Otter::Auth::DsList->new($self, [ ':main' ])->expanded_names;
        @main{@name} = (1) x @name;
    }

    my %out;
    foreach my $user (values %{ $self->all_users }) {
        my $ds = $user->write_datasets;

        # for "legacy" users_hash, skip the explicit default staff access
        if (my $is_staff = $user->email !~ /@/) {
            delete @{ $ds }{ keys %main };
            next if !keys %$ds;
        }

        my $email = $user->email;
        $email = lc($email) unless $preserve_case; # done in old _read_user_file

        $out{$email} = { map {($_ => 1)} keys %$ds };
    }

    return \%out;
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
