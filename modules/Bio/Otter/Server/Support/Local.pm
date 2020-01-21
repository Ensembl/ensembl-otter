=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Server::Support::Local;

use strict;
use warnings;

use Test::MockObject;
use base 'Bio::Otter::MappingFetcher';

sub new {
    my ($pkg, %options) = @_;

    my $self = $pkg->SUPER::new();

    # Sensible either-or left to instantiator to enforce
    $self->dataset_name($options{dataset}) if $options{dataset};
    $self->otter_dba($options{otter_dba})  if $options{otter_dba};
    $self->set_params(%{$options{params}}) if $options{params};

    return $self;
}

### Methods

sub authorized_user { # is deprecated in ::Web, move by renaming?
    my ($self, @args) = @_;
    ($self->{'_authorized_user'}) = @args if @args;
    return $self->authorized_user__catchable;
}

sub authorized_user__catchable {
    my ($self) = @_;
    my $user = $self->{'_authorized_user'};
    $user ||= getpwuid($<);
    return $user;
}

sub authenticated_username {
    my ($self) = @_;
    my $user = $self->authorized_user__catchable;
    # In ::Web this would be circular, because we authenticate before
    # authorising.  Here in ::Local we can be anyone.
    return $user;
}

sub require_method {
    my ($self, $want) = @_;
    # Caller would want an HTTP request with '$want' method
    return;
}

sub best_client_hostname {
    my $h = __PACKAGE__;
    $h =~ s{::}{.}g;
    return $h;
}

# If we're working locally, we assume we are a local user, but we warn about it.
sub local_user {
    warn __PACKAGE__, ": permitting local_user() access.\n";
    return 1;
}

### Accessors

sub content_type {
    my ($self, @args) = @_;
    ($self->{'content_type'}) = @args if @args;
    my $content_type = $self->{'content_type'};
    return $content_type;
}

sub dataset_name {
    my ($self, @args) = @_;
    ($self->{_dataset_name}) = @args if @args;
    return $self->{_dataset_name} || $self->require_argument('dataset');
}

sub set_params {
    my ($self, %params) = @_;
    return $self->{_params} = { %params };
}

sub add_param {
    my ($self, $key, $value) = @_;
    my $params = $self->{_params} ||= {};
    return $params->{$key} = $value;
}

sub param {
    my ($self, $key) = @_;
    my $params = $self->{_params};
    return unless $params;
    return $params->{$key};
}

sub cgi {
    my $cgi = Test::MockObject->new;
    $cgi->mock(user_agent => sub { __PACKAGE__.'/0.1' });
    return $cgi;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
