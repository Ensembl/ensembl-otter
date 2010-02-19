package Bio::Vega::PredictionTranscript;

use strict;
use warnings;

use base 'Bio::EnsEMBL::PredictionTranscript';

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
