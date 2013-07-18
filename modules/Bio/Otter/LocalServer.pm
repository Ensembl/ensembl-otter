package Bio::Otter::LocalServer;

use strict;
use warnings;

use base 'Bio::Otter::Server';

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
    my $uname = getpwuid($<);
    return $uname;
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
