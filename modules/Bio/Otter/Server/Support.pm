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

package Bio::Otter::Server::Support;

use strict;
use warnings;

=head1 NAME

Bio::Otter::Server::Support - common parent for MappingFetcher/B:O:Server::Support::{Local,Web}

=cut

use Carp;
use Try::Tiny;

use Bio::Otter::Server::Config;

sub new { # just to make it possible to instantiate an object
    my ($pkg, @arguments) = @_;

    my $self = bless { @arguments }, $pkg;
    return $self;
}

# In subclass:
#   authorized_user__catchable
#   authorized_user
#   authenticated_username


# Access control is applied during this call.
#
# Error text like m{^(\d{3}) (.*)$} is an HTTP status code
sub dataset {
    my ($self, $dataset) = @_;

    if($dataset) {
        $self->{'_dataset'} = $dataset;
    }

    return $self->{'_dataset'} ||= $self->_guarded_dataset($self->{'_authorized_user'});
}

# Return if user may write the dataset, or give a clear failure.
# Without this check, we would proceed on a read-only $dbh, then
# generate a more obscure error
sub dataset_assert_write {
    my ($self) = @_;
    die "403 Forbidden\n" if $self->dataset->READONLY;
    return;
}

sub dataset_name {
    die "no default dataset name";
}

# this is a local cache
sub Access {
    my ($self) = @_;
    my $acc = $self->{_Access} ||= Bio::Otter::Server::Config->Access();
    return $acc;
}

sub AccessUser {
    my ($self, $unauthorized_user) = @_;
    my $user = $self->Access->user($unauthorized_user);
    return $user;
}

sub allowed_datasets {
    my ($self, $unauthorized_user) = @_;
    my $user = $self->AccessUser($unauthorized_user);
    if (!defined $user) {
        # Provoke a login?
        my $username = $self->authorized_user; # may generate (real) 403 and exit
        warn "Username $username: authenticated, not authorized";
        die "403 Forbidden\n";
    } else {
        return [ values %{ $user->all_datasets } ];
    }
}

sub _guarded_dataset {
    my ($self, $unauthorized_user) = @_;
    my ($user, $dataset_name);
    return try {
        $user = $self->AccessUser($unauthorized_user) || die "user unknown\n";
        $dataset_name = $self->dataset_name;
        $user->all_datasets->{$dataset_name} || die "not in access.yaml\n";
    } catch {
        my $err = $_;

        # This is necessary to provoke the login mechanism of
        # Otter when authentication has not been done.  It does a
        # (real) 403 and then hard exit; our 403 below is munged to a
        # 412 in ::Web to circumvent re-login in the case of not
        # having access to a dataset.
        my $username = $self->{'_authorized_user'};

        $dataset_name = '(none)' unless defined $dataset_name;
        warn "Rejected user $username request for dataset $dataset_name: $err";
        die "403 Forbidden\n";
    };
}


# Access control is applied during ->dataset
sub otter_dba {
    my ($self, @args) = @_;

    if($self->{'_odba'} && !scalar(@args)) {   # cached value and no override
        return $self->{'_odba'};
    }

    my $adaptor_class = 'Bio::Vega::DBSQL::DBAdaptor';

    if(@args) { # let's check that the class is ok
        my $odba = shift @args;
        try { $odba->isa($adaptor_class) }
            or die "The object you assign to otter_dba must be a '$adaptor_class'";
        return $self->{'_odba'} = $odba;
    }

    return $self->{'_odba'} ||=
        $self->dataset->otter_dba;
}

sub require_argument {
    my ($self, $argname) = @_;

    my $value = $self->param($argname);

    confess "No '$argname' argument defined"
        unless defined $value;

    return $value;
}

sub require_arguments {
    my ($self, @arg_names) = @_;

    my %params = map { $_ => $self->require_argument($_) } @arg_names;
    return \%params;
}

############# Creation of an Author object #######

sub make_Author_obj {
    my ($self) = @_;

    my $author_name = $self->authorized_user;
    #my $author_email = $self->require_argument('email');

    return Bio::Vega::Author->new(
        -name  => $author_name,
        -email => $author_name,
        );
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
