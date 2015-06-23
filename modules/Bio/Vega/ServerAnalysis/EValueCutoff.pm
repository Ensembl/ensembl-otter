
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

