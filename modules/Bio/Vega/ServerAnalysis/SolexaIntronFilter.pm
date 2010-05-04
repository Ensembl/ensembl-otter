### Bio::Vega::ServerAnalysis::SolexaIntronFilter

package Bio::Vega::ServerAnalysis::SolexaIntronFilter;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub run {
    my ($self, $features) = @_;
    
    return @$features;
}


1;

__END__

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk