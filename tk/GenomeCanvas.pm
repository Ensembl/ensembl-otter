
### GenomeCanvas

package GenomeCanvas;


use strict;
use Carp;
use Tk;
use GenomeCanvas::MainWindow;
use GenomeCanvas::Band;
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
    
    $gc->bind_scroll_commands;
    
    return $gc;
}

sub bind_scroll_commands {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    my $x_scroll = $canvas->parent->Subwidget('xscrollbar');
    my $y_scroll = $canvas->parent->Subwidget('yscrollbar');
    $canvas->Tk::bind('<Enter>', sub{
        $canvas->Tk::focus;
        });
    
    # Don't want the scrollbars to take keyboard focus
    foreach my $widget ($x_scroll, $y_scroll) {
        $widget->configure(
            -takefocus => 0,
            );
    }
    $canvas->configure(
        -takefocus => 1,
        );
    return;
    
    # Home and End keys
    $canvas->bind('<Key-Home>', sub{
        $y_scroll->ScrlToPos(0);
        });
    $canvas->bind('<Key-End>', sub{
        $y_scroll->ScrlToPos(1);
        });
    
    # Page-Up and Page-Down keys
    $canvas->bind('<Key-Next>', sub{
        $y_scroll->ScrlByPages('v', 1);
        });
    $canvas->bind('<Key-Prior>', sub{
        $y_scroll->ScrlByPages('v', -1);
        });
    $canvas->bind('<Control-Key-Down>', sub{
        $y_scroll->ScrlByPages('v', 1);
        });
    $canvas->bind('<Control-Key-Up>', sub{
        $y_scroll->ScrlByPages('v', -1);
        });
    
    # Ctrl-Left and Ctrl-Right
    $canvas->bind('<Control-Key-Left>', sub{
        $x_scroll->ScrlByPages('h', -1);
        });
    $canvas->bind('<Control-Key-Right>', sub{
        $x_scroll->ScrlByPages('h', 1);
        });
    
    # Left and Right
    $canvas->bind('<Key-Left>', sub{
        $x_scroll->ScrlByUnits('h', -1);
        });
    $canvas->bind('<Key-Right>', sub{
        $x_scroll->ScrlByUnits('h', 1);
        });
    
    # Up and Down
    $canvas->bind('<Key-Up>', sub{
        $y_scroll->ScrlByUnits('v', -1);
        });
    $canvas->bind('<Key-Down>', sub{
        $y_scroll->ScrlByUnits('v', 1);
        });
}

sub scroll_to_obj {
    my( $gc, $obj ) = @_;
    
    confess "No object index given" unless $obj;
    
    my $canvas = $gc->canvas;
    my ($x1, $y1, $x2, $y2) = $gc->normalize_coords($canvas->bbox($obj));
    
    my $scroll_ref = $canvas->cget('scrollregion')
        or confess "No scrollregion";
    my @scroll = $gc->normalize_coords(@$scroll_ref);

    my $width  = $scroll[2] - $scroll[0];
    my $height = $scroll[3] - $scroll[1];
    #warn "width=$width, height=$height\n";
    
    my ($l_frac, $r_frac) = $canvas->xview;
    my $left  = $width * $l_frac;
    my $right = $width * $r_frac;
    #warn "left=$left, right=$right\n";
    if ($x2 < $left) {
        $canvas->xviewMoveto(($x1 - 10) / $width);
    }
    elsif ($x1 > $right) {
        my $visible_width = $right - $left;
        $canvas->xviewMoveto(($x2 + 10 - $visible_width) / $width);
    }
    else {
        #warn "object is visible in x axis\n";
    }
    
    my ($t_frac, $b_frac) = $canvas->yview;
    my $top  =   $height * $t_frac;
    my $bottom = $height * $b_frac;
    #warn "top=$top, bottom=$bottom\n";
    if ($y2 < $top) {
        $canvas->yviewMoveto(($y1 - 10) / $height);
    }
    elsif ($y1 > $bottom) {
        my $visible_height = $bottom - $top;
        $canvas->yviewMoveto(($y2 + 10 - $visible_height) / $height);
    } else {
        #warn "object is visible in x axis\n";
    }
}

sub normalize_coords {
    my( $gc, $x1, $y1, $x2, $y2 ) = @_;
    
    if ($x1 < 0) {
        $x1 = 0;
        $x2 = $x1 + $x2;
    }
    if ($y1 < 0) {
        $y1 = 0;
        $y2 = $y1 + $y2;
    }
    
    return ($x1, $y1, $x2, $y2);
}

    #foreach my $key_seq ($x_scroll->bind($class)) {
    #    my $x_com_ref = $x_scroll->bind($class, $key_seq);
    #    my $y_com_ref = $y_scroll->bind($class, $key_seq);
    #    if ($x_com_ref =~ /ARRAY/) {
    #        my($x_method, @x_args) = @$x_com_ref;
    #        my($y_method, @y_args) = @$y_com_ref;
    #        warn "\nx: $key_seq [$x_method, @x_args]\n";
    #        warn "y: $key_seq [$y_method, @y_args]\n";
    #    }
    #}

sub band_padding {
    my( $gc, $pixels ) = @_;
    
    if ($pixels) {
        $gc->{'_band_padding'} = $pixels;
    }
    return $gc->{'_band_padding'} || $gc->font_size * 2;
}

sub add_Band {
    my( $gc, $band ) = @_;
    
    $band->add_State($gc->state);
    push(@{$gc->{'_band_list'}}, $band);
}

sub band_list {
    my( $gc ) = @_;
    
    return @{$gc->{'_band_list'}};
}

sub render {
    my( $gc ) = @_;
    
    $gc->delete_all_bands;
    
    my $canvas = $gc->canvas;
    my $y_offset = 0;
    my $c = 0;
    my @band_list = $gc->band_list;
    for (my $i = 0; $i < @band_list; $i++) {
        my $band = $band_list[$i];
        my $tag = "$band-$i";
        if ($c > 0) {
            # Increase y_offset by the amount
            # given by band_padding
            $y_offset += $gc->band_padding;
        }
        $gc->band_tag($band, $tag);
        #warn "Rendering band '$tag' with offset $y_offset\n";
        
        $gc->y_offset($y_offset);
        $band->tags($tag);
        $band->render;
        $band->draw_titles if $band->can('draw_titles');

        #warn "[", join(',', $canvas->bbox($tag)), "]\n";

        # Move the band to the correct position if it
        # drew itself somewhere else
        $gc->draw_band_outline($band);
        my $actual_y = ($canvas->bbox($tag))[1] || $y_offset;
        if ($actual_y < $y_offset) {
            my $y_move = $y_offset - $actual_y;
            $canvas->move($tag, 0, $y_move);
        }

        #warn "[", join(',', $canvas->bbox($tag)), "]\n";

        $y_offset = ($canvas->bbox($tag))[3];
        $gc->y_offset($y_offset);
        $c++;
    }
}

sub draw_band_outline {
    my( $gc, $band ) = @_;
    
    my $canvas = $gc->canvas;
    my @tags = $band->tags;
    my @rect = $canvas->bbox(@tags)
        #or confess "Can't get bbox for tags [@tags]";
        or warn "Nothing drawn for [@tags]" and return;
    my $r = $canvas->createRectangle(
        @rect,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );
    $canvas->lower($r, 'all');
}

sub delete_all_bands {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    foreach my $band ($gc->band_list) {
        my $tag = $gc->band_tag($band);
        $canvas->delete($tag);
    }
}

sub band_tag {
    my( $gc, $band, $tag ) = @_;
    
    confess "Missing argument: no band" unless $band;
    
    if ($tag) {
        $gc->{'_band_tag_map'}{$band} = $tag;
    }
    return $gc->{'_band_tag_map'}{$band};
}

sub zoom {
    my( $gc, $zoom ) = @_;
    
    my $rpp = $gc->residues_per_pixel;
    my $canvas = $gc->canvas;
    
    # Calculate the coordinate of the centre of the view
    my $scroll_ref = $canvas->cget('scrollregion')
        or confess "No scrollregion";
    my ($x1, $y1, $x2, $y2) = @$scroll_ref;

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

sub set_window_size {
    my( $gc, $set_flag ) = @_;
    
    if ($set_flag) {
        my $mw = $gc->canvas->toplevel;
        my($x, $y) = $mw->geometry =~ /^(\d+)x(\d+)/;
        my ($display_max_x, $display_max_y) = $mw->maxsize;
        $x = $display_max_x if $x > $display_max_x;
        $y = $display_max_y if $y > $display_max_y;
        $gc->{'_set_window_size'} = [$x, $y];
    }
    if (my $xy = $gc->{'_set_window_size'}) {
        return @$xy;
    } else {
        return;
    }
}

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
    
    # Get the current screen offsets
    my($x, $y) = $mw->geometry =~ /^\d+x\d+\+?(-?\d+)\+?(-?\d+)/;

    # Is there a set window size?
    if (my($fix_x, $fix_y) = $gc->set_window_size) {
        $max_x = $fix_x;
        $max_y = $fix_y;
    } else {
        # Nudge the window onto the screen.
        $x = 0 if $x < 0;
        $y = 0 if $y < 0;

        if (($x + $max_x) > $display_max_x) {
            $x = $display_max_x - $max_x;
        }
        if (($y + $max_y) > $display_max_y) {
            $y = $display_max_y - $max_y;
        }
    }

    $mw->geometry("${max_x}x$max_y+$x+$y");
}

sub print_postscript {
    my( $gc, $file_root ) = @_;
    
    unless ($file_root) {
        $file_root = $gc->TopLevel->cget('title')
            || 'GenomeCanvas';
        $file_root =~ s/\s/_/g;
    }
    $file_root =~ s/\.ps$//i;
    
    my $canvas = $gc->canvas;
    my $bbox = $canvas->cget('scrollregion');
    my $canvas_width  = $bbox->[2] - $bbox->[0];
    my $canvas_height = $bbox->[3] - $bbox->[1];
    my $canvas_ratio = $canvas_width / $canvas_height;

    my $page_border = $gc->page_border;
    my $page_width  = $gc->page_width  - (2 * $page_border);
    my $page_height = $gc->page_height - (2 * $page_border);
    if ($page_width > $page_height) {
        confess "Page width must be greater than page height:\n",
            "  width = '$page_width', height = '$page_height'";
    }
    
    my $horiz_tile      = $gc->horizontal_tile;
    my $vert_tile       = $gc->vertical_tile;
    my $landscape       = $gc->landscape;
    my $tile_overlap    = $gc->tile_overlap;
    
    my $page_x = $page_border;
    my $page_y = $page_border;
    if ($landscape) {
        ($page_width, $page_height) = ($page_height, $page_width);
    } else {
        $page_y += $page_height;
    }
    
    my( $print_width, $print_height,
        $tile_width, $tile_height,
        $canvas_tile_pad,
        @ps_args );
    if ($horiz_tile) {
        my $overlap_count = $horiz_tile - 1;
        
        # Calculate the print width and height
        $print_width  = ($page_width * $horiz_tile) - ($tile_overlap * $overlap_count);
        $print_height = $print_width * ($canvas_height / $canvas_width);
        
        # Calculate size of tile overlap on canavs
        $canvas_tile_pad = $tile_overlap * ($canvas_width / $print_width);

        # Deduce the number of vertical tiles        
        $vert_tile = 1 + int($print_height / ($page_height - $tile_overlap));

        $tile_width  = ($canvas_width + ($overlap_count * $canvas_tile_pad)) / $horiz_tile;
        $tile_height = $tile_width  * ($page_height / $page_width);
        push(@ps_args, '-pagewidth', $page_width);
    }
    elsif ($vert_tile) {
        my $overlap_count = $vert_tile - 1;
        
        # Calculate print height and width
        $print_height = ($page_height * $vert_tile) - ($tile_overlap * $overlap_count);
        $print_width  = $print_height * ($canvas_width / $canvas_height);
        
        # Calculate size of tile overlap on canavs
        $canvas_tile_pad = $tile_overlap * ($canvas_height / $print_height);
        
        # Deduce the number of horizontal tiles
        $horiz_tile = 1 + int($print_width / ($page_width - $tile_overlap));
        
        $tile_height = ($canvas_height + ($overlap_count * $canvas_tile_pad)) / $vert_tile;
        $tile_width  = $tile_height  * ($page_width / $page_height);
        push(@ps_args, '-pageheight', $page_height);
    }
    else {
        $horiz_tile = 1;
        $vert_tile  = 1;
        $print_width  = $page_width;
        $print_height = $page_height;
        $tile_height = $canvas_height;
        $tile_width  = $canvas_width;
        $canvas_tile_pad = 0;
        my $print_ratio = $print_width / $print_height;
        if ($print_ratio < $canvas_ratio) {
            # May need to squish width
            if ($canvas_width > $print_width) {
                push(@ps_args, '-pagewidth', $print_width);
            }
        } else {
            # May need to squish height
            if ($canvas_height > $print_height) {
                push(@ps_args, '-pageheight', $print_height);
            }
        }
    }
    
    my $h_format = '%0'. length($horiz_tile) .'d';
    my $v_format = '%0'. length($vert_tile)  .'d';
    
    # Foreach row ...
    my( @ps_files );
    for (my $i = 0; $i < $vert_tile; $i++) {
        my $h_num = $vert_tile == 1 ? '' : sprintf($h_format, $i + 1);
        my $y = $bbox->[1] + ($i * $tile_height) - ($i * $canvas_tile_pad);
        
        # ... print each column
        for (my $j = 0; $j < $horiz_tile; $j++) {
            my $x = $bbox->[0] + ($j * $tile_width) - ($j * $canvas_tile_pad);
            my $v_num = $horiz_tile == 1 ? '' : sprintf($v_format, $j + 1);
            my( $ps_file_name );
            if ($horiz_tile == 1 and $vert_tile == 1) {
                $ps_file_name = "$file_root.ps";
            } else {
                my $join = ($v_num && $h_num) ? '-' : '';
                $ps_file_name = "$file_root-$v_num$join$h_num.ps";
            }
            
#            warn "\nps args =
#  -file => $ps_file_name,
#  '-x' => $x,
#  '-y' => $y,
#  -width  => $tile_width,
#  -height => $tile_height,
#  -pageanchor => 'nw',
#  -pagex => $page_x,
#  -pagey => $page_y,
#  -rotate => $landscape,
#  @ps_args,
#";
            
            $canvas->postscript(
                -file => $ps_file_name,
                '-x' => $x,
                '-y' => $y,
                -width  => $tile_width,
                -height => $tile_height,
                -pageanchor => 'nw',
                -pagex => $page_x,
                -pagey => $page_y,
                -rotate => $landscape,
                @ps_args,
                );
            push(@ps_files, $ps_file_name);
        }
    }
    return @ps_files;
}

sub page_width {
    my( $gc, $page_width ) = @_;
    
    if ($page_width) {
        confess "Illegal page width '$page_width'"
            unless $page_width =~ /^\d+$/;
        $gc->{'_page_width'} = $page_width;
    }
    return $gc->{'_page_width'}
        || 591; # A4 width in points
}

sub page_height {
    my( $gc, $page_height ) = @_;
    
    if ($page_height) {
        confess "Illegal page height '$page_height'"
            unless $page_height =~ /^\d+$/;
        $gc->{'_page_height'} = $page_height;
    }
    return $gc->{'_page_height'}
        || 841; # A4 height in points
}

sub page_border {
    my( $gc, $page_border ) = @_;
    
    if ($page_border) {
        confess "Illegal page border '$page_border'"
            unless $page_border =~ /^\d+$/;
        $gc->{'_page_border'} = $page_border;
    }
    return $gc->{'_page_border'}
        || 36; # half an inch in points
}

sub tile_overlap {
    my( $gc, $tile_overlap ) = @_;
    
    if ($tile_overlap) {
        confess "Illegal page border '$tile_overlap'"
            unless $tile_overlap =~ /^\d+$/;
        $gc->{'_tile_overlap'} = $tile_overlap;
    }
    return $gc->{'_tile_overlap'}
        || ($gc->page_border / 2);
}

sub landscape {
    my( $gc, $flag ) = @_;
    
    if (defined $flag) {
        $gc->{'_print_landscape'} = $flag ? 1 : 0;
    }
    $flag = $gc->{'_print_landscape'};
    return defined($flag) ? $flag : 0;
}


# Don't allow both horizontal and vertical tile to be set

sub horizontal_tile {
    my( $gc, $count ) = @_;
    
    if ($count) {
        confess "Illegal horizontal tile count '$count'"
            unless $count =~ /^\d+$/;
        $gc->{'_print_horizontal_tile'} = $count;
        $gc->{'_print_vertical_tile'}   = 0;
    }
    return $gc->{'_print_horizontal_tile'} || 0;
}

sub vertical_tile {
    my( $gc, $count ) = @_;
    
    if ($count) {
        confess "Illegal vertical tile count '$count'"
            unless $count =~ /^\d+$/;
        $gc->{'_print_horizontal_tile'} = 0;
        $gc->{'_print_vertical_tile'}   = $count;
    }
    return $gc->{'_print_vertical_tile'} || 0;
}

1;

__END__

=head1 NAME - GenomeCanvas

=head1 DESCRIPTION

GenomeCanvas is a container object for a
Tk::Canvas object, and one or many
GenomeCanvas::Band objects.

Each GenomeCanvas::Band object implements the
render method.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

