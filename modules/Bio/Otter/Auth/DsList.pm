=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Auth::DsList;
use strict;
use warnings;
use Try::Tiny;
use Carp;
use Scalar::Util 'weaken';


=head1 NAME

Bio::Otter::Auth::DsList - a list of datasets

=head1 DESCRIPTION

Class to hold a list of datasets for access control.

=head1 METHODS

Construct-only, with read-only attributes.

=cut


sub new {
    my ($pkg, $access, $dataset_names_list) = @_;
    my $self = bless {}, $pkg;

    # Access to species_groups is needed to expand them
    $self->{'_access'} = $access;
    weaken $self->{'_access'};
    confess "Made without _access" unless
      try{ $self->_access->can('species_groups') };

    $self->{'_names'} = $dataset_names_list;
    croak "$pkg->new needs arrayref of dataset names"
      unless ref($dataset_names_list);

    return $self;
}

sub clone_without {
    my ($obj, $exclude, $dropped) = @_;

    # Operate on expanded_names, because the set subtraction is more
    # complex with the species_groups
    my @keep;
    foreach my $name ($obj->expanded_names) {
        if (exists $exclude->{$name}) {
            push @$dropped, $name if $dropped;
        } else {
            push @keep, $name;
        }
    }

    my $pkg = ref($obj);
    return $pkg->new($obj->_access, \@keep);
}


sub _access {
    my ($self) = @_;
    return $self->{'_access'}
      || die "Lost my weakened _access";
}

sub raw_names {
    my ($self) = @_;
    return @{ $self->{'_names'} };
}

sub expanded_names {
    my ($self) = @_;
    my @name = $self->raw_names;
    @name = map { /^:(.*)$/ ? $self->_group($1) : $_ } @name;
    return @name;
}

sub _group {
    my ($self, $groupname) = @_;
    local $self->{'_LOOPING'} = 1;

    my $sp_grp = $self->_access->species_groups;
    die "Cannot resolve species_group $groupname without linkage"
      unless $sp_grp && ref($sp_grp);

    my $group = $sp_grp->{$groupname}; # expect another DsList
    die "Cannot resolve unknown species_group $groupname"
      unless defined $group;
    die "Loop detected while resolving species_group $groupname"
      if $group->{'_LOOPING'};

    return $group->expanded_names;
}


# Returns {name => $dataset_object}
sub datasets {
    my ($called, @dslist) = @_;
    push @dslist, $called if ref($called);
    die "No DsList objects" unless @dslist;

    my %ds;
    foreach my $list (@dslist) {
        my $species_dat = $list->_access->species_dat;
        foreach my $name ($list->expanded_names) {
            $ds{$name} = $species_dat->dataset($name)
              or die "Unknown dataset '$name'";
        }
    }
    return \%ds;
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
