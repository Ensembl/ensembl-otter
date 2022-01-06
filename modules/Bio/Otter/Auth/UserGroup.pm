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

package Bio::Otter::Auth::UserGroup;
use strict;
use warnings;
use Try::Tiny;
use Scalar::Util 'weaken';


=head1 NAME

Bio::Otter::Auth::UserGroup - a group of author, sharing some dataset names

=head1 DESCRIPTION

Class to hold access control information for one user group.

The non-private hash keys map directly to C<access.yaml> content.

=head1 METHODS

Construct-only, with read-only attributes.

=cut


sub new {
    my ($pkg, $access, $hashref) = @_;
    my $self = bless { _access => $access }, $pkg;
    weaken $self->{'_access'};

    my %info = %$hashref;
    foreach my $key (qw( write read comment )) {
        $self->{$key} = delete $info{$key} if exists $info{$key};
    }

    $self->{'_users'} = $self->_build_users(delete $info{users});

    my @badkey = sort keys %info;
    die "$pkg->new: unexpected subkeys (@badkey)" if @badkey;

    return $self;
}

sub _access {
    my ($self) = @_;
    return $self->{'_access'}
      || die "Lost my weakened _access";
}

sub comment {
    my ($self) = @_;
    return $self->{'comment'};
}

sub users {
    my ($self) = @_;
    return @{ $self->{'_users'} };
}

sub _build_users {
    my ($self, $userlist) = @_;
    my @out = map { Bio::Otter::Auth::User->new($self->_access, $_) } $userlist;
    foreach my $u (@out) {
        $u->in_group($self);
    }
    return \@out;
}

sub _write {
    my ($self) = @_;
    return $self->{'write'} || [];
}

sub _read {
    my ($self) = @_;
    return $self->{'read'} || [];
}

sub write_list {
    my ($self) = @_;
    return $self->{'_write_dslist'} ||=
      Bio::Otter::Auth::DsList->new($self->_access, $self->_write);
}

sub read_list {
    my ($self) = @_;
    return $self->{'_read_dslist'} ||=
      Bio::Otter::Auth::DsList->new($self->_access, $self->_read);
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
