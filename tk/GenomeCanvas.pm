
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

use vars qw{@ISA @DEFAULT_CANVAS_SIZE};
@ISA = ('GenomeCanvas::State');

@DEFAULT_CANVAS_SIZE = (500,50);

sub new {
    my( $pkg, $tk ) = @_;
    
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
        -width              => $DEFAULT_CANVAS_SIZE[0],
        -height             => $DEFAULT_CANVAS_SIZE[1],
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

sub bandset_padding {
    my( $gc, $pixels ) = @_;
    
    if ($pixels) {
        $gc->{'_bandset_padding'} = $pixels;
    }
    return $gc->{'_bandset_padding'} || 20;
}

sub render {
    my( $gc ) = @_;
    
    $gc->delete_all_bandsets;
    
    my $canvas = $gc->canvas;
    my $y_offset = 0;
    my $c = 0;
    foreach my $set ($gc->band_sets) {
        if ($c > 0) {
            # Increase y_offset by the amount
            # given by bandset_padding
            $y_offset += $gc->bandset_padding;
        }
        $gc->y_offset($y_offset);
        my $tag = $gc->bandset_tag($set);
        #warn "Rendering bandset '$tag' with offset $y_offset\n";
        
        $set->render($tag);

        #warn "[", join(',', $canvas->bbox($tag)), "]\n";

        # Move the band to the correct position if it
        # drew itself somewhere else
        my $actual_y = ($canvas->bbox($tag))[1];
        if ($actual_y < $y_offset) {
            my $y_move = $y_offset - $actual_y;
            $canvas->move($tag, 0, $y_move);
        }

        #warn "[", join(',', $canvas->bbox($tag)), "]\n";

        $y_offset = ($canvas->bbox($tag))[3];
        $c++;
    }
    
}

sub delete_all_bandsets {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    foreach my $set ($gc->band_sets) {
        my $tag = $gc->bandset_tag($set);
        $canvas->delete($tag);
    }
}

sub new_BandSet {
    my( $gc ) = @_;
    
    my $band_set = GenomeCanvas::BandSet->new;
    push( @{$gc->{'_band_sets'}}, $band_set );
    $band_set->add_State($gc->state);

    # Add a tag which identifies this set on the canvas
    my $tag = 'set_'. scalar(@{$gc->{'_band_sets'}});
    $band_set->bandset_tag($tag);
    $gc->bandset_tag($band_set, $tag);
    
    return $band_set;
}

sub bandset_tag {
    my( $gc, $set, $tag ) = @_;
    
    confess "Missing argument: no bandset" unless $set;
    
    if ($tag) {
        $gc->{'_bandset_tag_map'}{$set} = $tag;
    }
    return $gc->{'_bandset_tag_map'}{$set};
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
    $canvas->configure(-scrollregion => [$x1, $y1, $x2, $y2]);

    # center on x axis
    my @x_view = $canvas->xview;
    my $x_view_center_fraction = $x_view[0] + (($x_view[1] - $x_view[0]) / 2);
    my $x_view_center_coord = $x1 + (($x2 - $x1) * $x_view_center_fraction);   

    # center on y axis
    my @y_view = $canvas->yview;
    my $y_view_center_fraction = $y_view[0] + (($y_view[1] - $y_view[0]) / 2);
    my $y_view_center_coord = $y1 + (($y2 - $y1) * $y_view_center_fraction);
    

    # Used for debugging, this drew a small red square
    # in the centre of the visible canvas:
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
    #$canvas->scale('all', $x_view_center_coord, $y_view_center_coord, $x_zoom_factor, 1);
    $canvas->scale('all', 0,0, $x_zoom_factor, 1);
    
    $gc->residues_per_pixel($new_rpp);
    $gc->fix_window_min_max_sizes;
}

sub set_scroll_region {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    my @bbox = $canvas->bbox('all');
    $gc->expand_bbox(\@bbox, 5);
    $canvas->configure(
        -scrollregion => [@bbox],
        );
    return @bbox;
}

#sub screen_dimensions {
#    my( $gc, @max ) = @_;
#    
#    if (@max) {
#        $gc->{'_screen_dimensions'} = [@max];
#    }
#    return @{$gc->{'_screen_dimensions'}};
#}
#
#sub other_widgets_size {
#    my( $gc, @other ) = @_;
#    
#    if (@other) {
#        $gc->{'_other_widgets_size'} = [@other];
#    }
#    return @{$gc->{'_other_widgets_size'}};
#}

sub fix_window_min_max_sizes {
    my( $gc ) = @_;
    
    my $mw = $gc->canvas->toplevel;
    $mw->update;

    my( $other_x, # other_x and other_y record the space occupied
        $other_y, # by the widgets other than the canvas in the
                  # window.
        $display_max_x, # display_max_x and display_max_y record
        $display_max_y, # the dimensions of the display.
        );
    if (my $mm = $gc->{'_toplevel_other_max'}) {
        ($other_x, $other_y, $display_max_x, $display_max_y) = @$mm;
    } else {
        my $width  = $mw->width;
        my $height = $mw->height;
        $mw->minsize($width, $height);

        $other_x = $width  - $DEFAULT_CANVAS_SIZE[0];
        $other_y = $height - $DEFAULT_CANVAS_SIZE[1];

        ($display_max_x, $display_max_y) = $mw->maxsize;
        $gc->{'_toplevel_other_max'} = [$other_x, $other_y, $display_max_x, $display_max_y];
        $mw->resizable(1,1);
    }
    
    my @bbox = $gc->set_scroll_region;
    my $canvas_width  = $bbox[2] - $bbox[0];
    my $canvas_height = $bbox[3] - $bbox[1];

    my $max_x = $canvas_width  + $other_x;
    my $max_y = $canvas_height + $other_y;
    $max_x = $display_max_x if $max_x > $display_max_x;
    $max_y = $display_max_y if $max_y > $display_max_y;
    $mw->maxsize($max_x, $max_y);
    

    # Nudge the window onto the screen.
    my($x, $y) = $mw->geometry =~ /^\d+x\d+\+?(-?\d+)\+?(-?\d+)/;
    $x = 0 if $x < 0;
    $y = 0 if $y < 0;

    if (($x + $max_x) > $display_max_x) {
        $x = $display_max_x - $max_x;
    }
    if (($y + $max_y) > $display_max_y) {
        $y = $display_max_y - $max_y;
    }

    $mw->geometry("${max_x}x$max_y+$x+$y");
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

