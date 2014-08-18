package Bio::Otter::Server::Support::Local;

use strict;
use warnings;

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

sub authorized_user {
    my ($self, @args) = @_;
    ($self->{'_authorized_user'}) = @args if @args;
    my $authorized_user = $self->{'_authorized_user'};
    $authorized_user ||= getpwuid($<);
    return $authorized_user;
}

sub require_method {
    my ($self, $want) = @_;
    # Caller would want an HTTP request with '$want' method
    return;
}

### Accessors

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

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
