
### GenomeCanvas

package GenomeCanvas;

use strict;
use Carp;
use Tk;
use GenomeCanvas::MainWindow;
use GenomeCanvas::Band;
use GenomeCanvas::BandSet;
use GenomeCanvas::Drawable;

sub new {
    my( $pkg, $tk ) = @_;
    
    unless ($tk) {
        confess "Error usage: GenomeCanvas->new(<Tk::Widget object>)";
    }
    
    my $gc = bless {}, $pkg;
    
    # Create and store the canvas object
    my $scrolled = $tk->Scrolled('Canvas',
        -highlightthickness => 1,
        -background         => 'white',
        -scrollbars         => 'se',
        -width              => 500,
        -height             => 200,
        );
    $scrolled->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
        );
        
    my $canvas = $scrolled->Subwidget('canvas');
    $gc->canvas($canvas);    
    return $gc;
}

sub canvas {
    my( $gc, $canvas ) = @_;
    
    if ($canvas) {
        confess("Not a Tk::Canvas object '$canvas'")
            unless ref($canvas) and $canvas->isa('Tk::Canvas');
        $gc->{'_canvas'} = $canvas;
    }
    return $gc->{'_canvas'};
}

sub render {
    my( $gc ) = @_;
    
    foreach my $set ($gc->band_sets) {
        $set->render($gc->canvas);
    }
}

sub new_BandSet {
    my( $gc ) = @_;
    
    my $band_set = GenomeCanvas::BandSet->new;
    push( @{$gc->{'_band_sets'}}, $band_set );
    return $band_set;
}

sub band_sets {
    my( $gc ) = @_;
    
    return @{$gc->{'_band_sets'}};
}

1;

__END__

=head1 NAME - GenomeCanvas

=head1 DESCRIPTION

GenomeCanvas is a container object for a
Tk::Canvas object, and one or many
GenomeCanvas::BandSet objects.

Each GenomeCanvas::BandSet object contains a
Bio::EnsEMBL::Virtual::Contig object, and one or
many GenomeCanvas::Band objects.

Each GenomeCanvas::Band contains an array
containing one or many GenomeCanvas::Drawable
objects, in the order in which they are drawn
onto the canvas.  To render each Drawable object,
the Band object passes the appropriate data as
arguments to the draw() method on the Drawable.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

