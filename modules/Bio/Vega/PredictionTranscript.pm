=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

