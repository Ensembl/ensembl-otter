=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Vega::ServerAnalysis::EValueCutoff

package Bio::Vega::ServerAnalysis::EValueCutoff;

use strict;
use warnings;
use base qw{ Bio::Vega::ServerAnalysis };

sub run {
    my ($self, $features) = @_;
    
    my $max_e_value = $self->Web->require_argument('max_e_value');

    for (my $i = 0; $i < @$features;) {
        if ($features->[$i]->p_value > $max_e_value) {
            splice(@$features, $i, 1);
        }
        else {
            $i++;
        }
    }

    return $features;
}

1;

__END__

=head1 NAME - Bio::Vega::ServerAnalysis::EValueCutoff

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

