package Bio::Otter::LocalServer;

use strict;
use warnings;

use base 'Bio::Otter::Server';

sub new {
    my ($pkg, $params) = @_;

    my $self = { };
    my $class = ref($pkg) || $pkg;
    bless $self, $class;

    # Sensible either-or left to instantiator to enforce
    $self->dataset_name($params->{dataset}) if $params->{dataset};
    $self->otter_dba($params->{otter_dba})  if $params->{otter_dba};

    return $self;
}

### Methods



### Accessors

sub dataset_name {
    my ($self, @args) = @_;
    ($self->{_dataset_name}) = @args if @args;
    return $self->{_dataset_name};
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
