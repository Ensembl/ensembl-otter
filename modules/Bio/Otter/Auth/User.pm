package Bio::Otter::Auth::User;
use strict;
use warnings;
use Try::Tiny;
use Scalar::Util 'weaken';

=head1 NAME

Bio::Otter::Auth::User - an author, dataset independent

=head1 DESCRIPTION

Class to hold access control information for one user.

The non-private hash keys map directly to C<access.yaml> content,
therefore the user's full access will depend on the context in which
it is stored.

=head1 METHODS

Construct-only, with read-only attributes.

Except L</in_group>, which is write-once to connect up users to groups
after all other data is loaded.

=cut


sub new {
    my ($pkg, $access, $hashref_or_name) = @_; 
    my $self = bless { _access => $access }, $pkg;
    weaken $self->{'_access'};

    if (ref($hashref_or_name)) {
        my @email = try { keys %$hashref_or_name };
        die "$pkg->new hashref: expected one email key, got (@email)"
          unless 1==@email;
        my $e = $self->{'_email'} = $email[0];
        my $data = $hashref_or_name->{$e};
        die "Empty user spec for $e - trailing : in YAML?" unless $data;

        my %info = %$data;
        foreach my $key (qw( read write comment )) {
            $self->{$key} = delete $info{$key} if exists $info{$key};
        }
        my @badkey = sort keys %info;
        die "$pkg->new for $e: unexpected subkeys (@badkey)" if @badkey;

    } else {
        $self->{'_email'} = $hashref_or_name;
    }

    return $self;
}

#sub reyaml {
#    my ($self) = @_;
#    my $e = $self->email;
#    my %info = map {( $_ => $self->{$_} )}
#      grep { ! /^_/ } keys %$self;
#    return keys %info ? { $e => \%info } : $e;
#}

sub _access {
    my ($self) = @_;
    return $self->{'_access'}
      || die "Lost my weakened _access";
}

sub email {
    my ($self) = @_;
    return $self->{'_email'};
}

sub comment {
    my ($self) = @_;
    return $self->{'comment'};
}

sub _more_write {
    my ($self) = @_;
    return $self->{'write'};
}

sub _more_read {
    my ($self) = @_;
    return $self->{'read'};
}


sub _write_list {
    my ($self) = @_;
    if (my $mw = $self->_more_write) {
        return Bio::Otter::Auth::DsList->new($self->_access, $mw);
    } else {
        return ();
    }
}

sub _read_list {
    my ($self) = @_;
    if (my $mw = $self->_more_read) {
        return $self->{'_read_dslist'} ||=
          Bio::Otter::Auth::DsList->new($self->_access, $mw);
    } else {
        return ();
    }
}

# Multi-group membership is possible here, but currently not permitted
# by BOA:UserGroup->_build_users or BOA:Access->_flatten_users .
#
# Plan in RT#355854 was mutli-group membership when explicitly marked
# in each place the user exists in a group, to avoid confusion.
# Also, beware email address case differences between groups.
#
# UserGroups are part of the configuration interface (via YAML), but
# not particularly intended to be useful in the API.
sub in_group {
    my ($self, @ugroup) = @_;
    my $e = $self->email;
    if (@ugroup) {
        die "User $e has _in_group already" if $self->{'_in_group'};
        $self->{_in_group} = [ @ugroup ];
        foreach my $i (0..$#ugroup) {
            weaken($ugroup[$i]);
        }
    }
    my $glist = $self->{'_in_group'}
      or die "User $e _in_group is not yet set";
    return @$glist;
}

# Returns a list of DsList
sub write_lists {
    my ($self) = @_;
    return @{ $self->{_write_dslists} } if $self->{_write_dslists};

    my @w = ($self->_write_list,
             map { $_->write_list } $self->in_group);

    # Ugliness which comes from too much input flexibility
    my @ro;
    foreach my $read ($self->read_lists) {
        push @ro, $read->expanded_names;
    }
    if (@ro) {
        # Need to exclude some read-only datasets from write_list, for
        # datasets and species_groups.
        my %ro = map {($_ => 1)} @ro;
        my @dropped;
        @w = map { $_->clone_without(\%ro, \@dropped) } @w;
        my $e = $self->email;
        warn "User $e has both read+write on (@dropped), taken as read only"
          if @dropped;
    }

    $self->{_write_dslists} = \@w;
    return @w;
}

sub read_lists {
    my ($self) = @_;
    my @r = ($self->_read_list,
             map { $_->read_list } $self->in_group);
    return @r;
}


# Returns {name => $dataset_object}
sub all_datasets {
    my ($self) = @_;
    my %all = (%{ $self->read_datasets  },
               %{ $self->write_datasets });
    return \%all;
}

# Returns {name => $dataset_object}
sub write_datasets {
    my ($self) = @_; 
    return Bio::Otter::Auth::DsList->datasets( $self->write_lists );
}

# Returns {name => $dataset_object}
sub read_datasets {
    my ($self) = @_;
    my $rw = Bio::Otter::Auth::DsList->datasets( $self->read_lists );
    my %ro;
    @ro{ keys %$rw } = map { $_->clone_readonly } values %$rw;
    return \%ro;
}

# Returns $dataset_object or undef
sub write_dataset {
    my ($self, $dataset_name) = @_; 
    return $self->write_datasets->{$dataset_name};
}

# Returns $dataset_object or undef
sub read_dataset {
    my ($self, $dataset_name) = @_;
    return $self->read_datasets->{$dataset_name};
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
