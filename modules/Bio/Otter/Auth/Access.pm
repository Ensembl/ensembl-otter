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

=head1 DESCRIPTION

Class to collect all access control for users to datasets.

=head2 Overview

Access holds a L<Bio::Otter::SpeciesDat>, so dataset names can be
checked.

It uses L<Bio::Otter::Auth::DsList> to hold lists of datasets, for the
species groups and for the access lists of user groups and usesrs.

=head1 METHODS

Construct-only, with read-only attributes.

=cut


sub new {
    my ($pkg, $hashref, $species_dat) = @_;
    my $self = { _species_dat => $species_dat,
                 _input => $hashref };
    bless $self, $pkg;

    local $self->{_ptr}; # where we are up to, with parsing
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

# Returns a BOA:User or undef if not found
sub user {
    my ($self, $email) = @_;
    return $self->{_users}->{lc($email)};
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


sub legacy_users_hash {
    my ($self, @opt) = @_;
    my $preserve_case = ("@opt" eq 'samecase'); # for testing

    my %main; # names of the unrestricted datasets
    {
        my @name = Bio::Otter::Auth::DsList->new($self, [ ':main' ])->expanded_names;
        @main{@name} = (1) x @name;
    }

    my %out;
    foreach my $user (values %{ $self->{_users} }) {
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

1;
