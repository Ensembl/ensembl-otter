
### GenomeCanvas::BandSet

package GenomeCanvas::BandSet;

use strict;
use Carp;
use GenomeCanvas::State;

use vars '@ISA';
@ISA = ('GenomeCanvas::State');

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub add_Band {
    my( $set, $band ) = @_;
    
    $band->add_State($set->state);
    push(@{$set->{'_band_list'}}, $band);
}

sub band_list {
    my( $set ) = @_;
    
    return @{$set->{'_band_list'}};
}

sub render {
    my( $set ) = @_;
    
    foreach my $band ($set->band_list) {
        $band->render;
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::BandSet

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

