
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

sub bandset_tag {
     my( $set, $tag ) = @_;
     
     if ($tag) {
        if (my $old = $set->{'_bandset_tag'}) {
            warn "Changing bandset_tag from '$old' to '$tag'";
        }
        $set->{'_bandset_tag'} = $tag;
     }
     return $set->{'_bandset_tag'};
}

sub render {
    my( $set ) = @_;
    
    my( @bbox );
    my $canvas   = $set->canvas;
    my $tag      = $set->bandset_tag;
    $canvas->delete($tag);
    foreach my $band ($set->band_list) {
        $band->tags($tag);
        $band->render();
    }
    
    $set->draw_set_outline;
}

sub draw_set_outline {
    my( $set ) = @_;
    
    my $canvas = $set->canvas;
    my $tag = $set->bandset_tag;
    my @rect = $canvas->bbox($tag)
        or confess "Can't get bbox for tag '$tag'";
    $canvas->createRectangle(
        @rect,
        -fill       => undef,
        -outline    => undef,
        -tags       => [$tag],
        );
}

1;

__END__

=head1 NAME - GenomeCanvas::BandSet

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

