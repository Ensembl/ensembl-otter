
### GenomeCanvas

package GenomeCanvas;

use strict;
use Carp;
use Tk;
use GenomeCanvas::MainWindow;
use GenomeCanvas::Band;
use GenomeCanvas::BandSet;
use GenomeCanvas::Drawable;
use GenomeCanvas::State;

use vars '@ISA';
@ISA = ('GenomeCanvas::State');

sub new {
    my( $pkg, $tk, $width, $height ) = @_;
    
    $width  ||= 500;
    $height ||= 200;
    
    unless ($tk) {
        confess "Error usage: GenomeCanvas->new(<Tk::Widget object>)";
    }
    
    my $gc = bless {}, $pkg;
    $gc->new_State;
    
    # Create and store the canvas object
    my $scrolled = $tk->Scrolled('Canvas',
        -highlightthickness => 1,
        -background         => 'white',
        -scrollbars         => 'se',
        -width              => $width,
        -height             => $height,
        );
    $scrolled->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
        );
        
    my $canvas = $scrolled->Subwidget('canvas');
    $gc->canvas($canvas);
    $gc->window_width($width);
    $gc->window_height($height);
    return $gc;
}

sub window_width {
    my( $gc, $n ) = @_;
    
    if ($n) {
        confess "Can't reset window_width"
            if $gc->{'_window_width'};
        $gc->{'_window_width'} = $n;
    }
    return $gc->{'_window_width'};
}

sub window_height {
    my( $gc, $n ) = @_;
    
    if ($n) {
        confess "Can't reset window_height"
            if $gc->{'_window_height'};
        $gc->{'_window_height'} = $n;
    }
    return $gc->{'_window_height'};
}

sub band_padding {
    my( $gc, $pixels ) = @_;
    
    if ($pixels) {
        $gc->{'_band_padding'} = $pixels;
    }
    return $gc->{'_band_padding'} || 20;
}

sub render {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    my ($x_origin, $y_origin) = (0,0);
    foreach my $set ($gc->band_sets) {
        $set->render;
        
        # Expand the frame down the y axis by the
        # amount given by band_padding
        my @bbox = $gc->frame;
        $bbox[3] += $gc->band_padding;
        $gc->frame(@bbox);
    }
}

sub new_BandSet {
    my( $gc ) = @_;
    
    my $band_set = GenomeCanvas::BandSet->new;
    push( @{$gc->{'_band_sets'}}, $band_set );
    $band_set->add_State($gc->state);
    return $band_set;
}

sub band_sets {
    my( $gc ) = @_;
    
    return @{$gc->{'_band_sets'}};
}

sub zoom {
    my( $gc, $zoom ) = @_;
    
    my $rpp = $gc->residues_per_pixel;
    my $canvas = $gc->canvas;
    
    # Calculate the coordinate of the centre of the view
    my ($x1, $y1, $x2, $y2) = $canvas->cget('scrollregion');
    #$canvas->configure(
    #    -scrollregion => [$x1, $y1, $x2, $y2],
    #    );

    # center on x axis
    my @x_view = $canvas->xview;
    my $x_view_center_fraction = $x_view[0] + (($x_view[1] - $x_view[0]) / 2);
    my $x_view_center_coord = $x1 + (($x2 - $x1) * $x_view_center_fraction);   

    # center on y axis
    my @y_view = $canvas->yview;
    my $y_view_center_fraction = $y_view[0] + (($y_view[1] - $y_view[0]) / 2);
    my $y_view_center_coord = $y1 + (($y2 - $y1) * $y_view_center_fraction);
    
    #{
    #    my $x = $x_view_center_coord;
    #    my $y = $y_view_center_coord;
    #    my @rectangle = ($x-2, $y-2, $x+2, $y+2);
    #    $canvas->createRectangle(
    #        @rectangle,
    #        -fill       => 'red',
    #        -outline    => undef,
    #        );
    #}
    
    # Calculate the new number of residues per pixel
    my( $new_rpp );
    if ($zoom > 0) {
        $new_rpp = $rpp / $zoom;
    }
    elsif ($zoom < 0) {
        $zoom *= -1;
        $new_rpp = $rpp * $zoom;
    }
    else {
        return;
    }
    warn "rpp=$new_rpp\n";
    
    my $x_zoom_factor = $rpp / $new_rpp;
    $canvas->scale('all', $x_view_center_coord, $y_view_center_coord, $x_zoom_factor, 1);
    
    $gc->residues_per_pixel($new_rpp);
    $gc->fix_window_min_max_sizes;
}

sub fix_window_min_max_sizes {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    
    my @bbox = $canvas->bbox('all');
    $gc->expand_bbox(\@bbox, 5);
    $canvas->configure(
        -scrollregion => [@bbox],
        );

    my $mw = $canvas->toplevel;
    $mw->update;
    $mw->minsize($mw->width, $mw->height);
    my( $screen_max_x, $screen_max_y ) = $mw->maxsize;
    my $max_x = $bbox[2] - $bbox[0] + $mw->width  - $gc->window_width;
    my $max_y = $bbox[3] - $bbox[1] + $mw->height - $gc->window_height;
    $max_x = $screen_max_x if $max_x > $screen_max_x;
    $max_y = $screen_max_y if $max_y > $screen_max_y;
    $mw->maxsize($max_x, $max_y);
    $mw->resizable(1,1);
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

