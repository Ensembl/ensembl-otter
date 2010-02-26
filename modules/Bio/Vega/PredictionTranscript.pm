package Bio::Vega::PredictionTranscript;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Argument qw( rearrange );

use base 'Bio::EnsEMBL::PredictionTranscript';

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    my ($truncated_5_prime, $truncated_3_prime) = rearrange([
        'TRUNCATED_5_PRIME',
        'TRUNCATED_3_PRIME'
    ], @_);
    
    $self->{truncated_5_prime} = $truncated_5_prime;
    $self->{truncated_3_prime} = $truncated_3_prime;

    return $self;
}

sub truncated_5_prime {
    my $self = shift;
    $self->{truncated_5_prime} = shift if @_;
    return $self->{truncated_5_prime};
}

sub truncated_3_prime {
    my $self = shift;
    $self->{truncated_3_prime} = shift if @_;
    return $self->{truncated_3_prime};
}

1;
