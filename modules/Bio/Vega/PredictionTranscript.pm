package Bio::Vega::PredictionTranscript;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Argument qw( rearrange );

use base 'Bio::EnsEMBL::PredictionTranscript';

sub new {
    my ($class, @args) = shift;

    my $self = $class->SUPER::new(@args);

    my ($truncated_5_prime, $truncated_3_prime) = rearrange([
        'TRUNCATED_5_PRIME',
        'TRUNCATED_3_PRIME'
    ], @args);

    $self->{truncated_5_prime} = $truncated_5_prime;
    $self->{truncated_3_prime} = $truncated_3_prime;

    return $self;
}

sub truncated_5_prime {
    my ($self, @args) = @_;
    $self->{truncated_5_prime} = shift @args if @args;
    return $self->{truncated_5_prime};
}

sub truncated_3_prime {
    my ($self, @args) = @_;
    $self->{truncated_3_prime} = shift @args if @args;
    return $self->{truncated_3_prime};
}

1;

__END__

=head1 NAME - Bio::Vega::PredictionTranscript

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

