
### Bio::Vega::ServerAnalysis

package Bio::Vega::ServerAnalysis;

use strict;
use warnings;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

# Bio::Otter::Server::Support::Web object for access to config file params
sub Web {
    my ($self, $Web) = @_;
    
    if ($Web) {
        $self->{'_Web'} = $Web;
    }
    return $self->{'_Web'};
}


1;

__END__

=head1 NAME - Bio::Vega::ServerAnalysis

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

