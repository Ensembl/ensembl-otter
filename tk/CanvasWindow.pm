
### CanvasWindow

package CanvasWindow;

use strict;
use Carp;
use CanvasWindow::MainWindow;
use CanvasWindow::Utils 'expand_bbox';

use vars ('@DEFAULT_CANVAS_SIZE');

@DEFAULT_CANVAS_SIZE = (500,50);

sub new {
    my( $pkg, $tk ) = @_;
    
    unless ($tk) {
        confess "Error usage: $pkg->new(<Tk::Widget object>)";
    }

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
    
    # Make a new CanvasWindow object, and return
    my $self = bless {}, $pkg;
    $self->canvas($canvas);
    $self->bind_scroll_commands;
    
    return $self;
}

sub canvas {
    my( $self, $canvas ) = @_;
    
    if ($canvas) {
        confess("Not a Tk::Canvas object '$canvas'")
            unless ref($canvas) and $canvas->isa('Tk::Canvas');
        $self->{'_canvas'} = $canvas;
    }
    return $self->{'_canvas'};
}

sub set_scroll_region {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my @bbox = $canvas->bbox('all');
    expand_bbox(\@bbox, 5);
    $canvas->configure(
        -scrollregion => [@bbox],
        );
    return @bbox;
}

sub bind_scroll_commands {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
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


sub scroll_to_obj {
    my( $self, $obj ) = @_;
    
    confess "No object index given" unless $obj;
    
    my $canvas = $self->canvas;
    my ($x1, $y1, $x2, $y2) = $self->normalize_coords($canvas->bbox($obj));
    
    my $scroll_ref = $canvas->cget('scrollregion')
        or confess "No scrollregion";
    my @scroll = $self->normalize_coords(@$scroll_ref);

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
    my( $self, $x1, $y1, $x2, $y2 ) = @_;
    
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


sub fix_window_min_max_sizes {
    my( $self ) = @_;
    
    my $mw = $self->canvas->toplevel;
    $mw->update;

    my( $other_x, # other_x and other_y record the space occupied
        $other_y, # by the widgets other than the canvas in the
                  # window.
        $display_max_x, # display_max_x and display_max_y record
        $display_max_y, # the dimensions of the display.
        );
    if (my $mm = $self->{'_toplevel_other_max'}) {
        ($other_x, $other_y, $display_max_x, $display_max_y) = @$mm;
    } else {
        my $width  = $mw->width;
        my $height = $mw->height;
        $mw->minsize($width, $height);

        $other_x = $width  - $DEFAULT_CANVAS_SIZE[0];
        $other_y = $height - $DEFAULT_CANVAS_SIZE[1];

        ($display_max_x, $display_max_y) = $mw->maxsize;
        $self->{'_toplevel_other_max'} = [$other_x, $other_y, $display_max_x, $display_max_y];
        $mw->resizable(1,1);
    }
    
    my @bbox = $self->set_scroll_region;
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
    if (my($fix_x, $fix_y) = $self->set_window_size) {
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

sub set_window_size {
    my( $self, $set_flag ) = @_;
    
    if ($set_flag) {
        my $mw = $self->canvas->toplevel;
        my($x, $y) = $mw->geometry =~ /^(\d+)x(\d+)/;
        my ($display_max_x, $display_max_y) = $mw->maxsize;
        $x = $display_max_x if $x > $display_max_x;
        $y = $display_max_y if $y > $display_max_y;
        $self->{'_set_window_size'} = [$x, $y];
    }
    if (my $xy = $self->{'_set_window_size'}) {
        return @$xy;
    } else {
        return;
    }
}

sub print_postscript {
    my( $self, $file_root ) = @_;
    
    unless ($file_root) {
        $file_root = $self->TopLevel->cget('title')
            || 'GenomeCanvas';
        $file_root =~ s/\s/_/g;
    }
    $file_root =~ s/\.ps$//i;
    
    my $canvas = $self->canvas;
    my $bbox = $canvas->cget('scrollregion');
    my $canvas_width  = $bbox->[2] - $bbox->[0];
    my $canvas_height = $bbox->[3] - $bbox->[1];
    my $canvas_ratio = $canvas_width / $canvas_height;

    my $page_border = $self->page_border;
    my $page_width  = $self->page_width  - (2 * $page_border);
    my $page_height = $self->page_height - (2 * $page_border);
    #if ($page_width > $page_height) {
    #    confess "Page width must be greater than page height:\n",
    #        "  width = '$page_width', height = '$page_height'";
    #}
    
    my $horiz_tile      = $self->horizontal_tile;
    my $vert_tile       = $self->vertical_tile;
    my $landscape       = $self->landscape;
    my $tile_overlap    = $self->tile_overlap;
    
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
        my $v_num = $vert_tile == 1 ? '' : sprintf($v_format, $i + 1);
        my $y = $bbox->[1] + ($i * $tile_height) - ($i * $canvas_tile_pad);
        
        # ... print each column
        for (my $j = 0; $j < $horiz_tile; $j++) {
            my $x = $bbox->[0] + ($j * $tile_width) - ($j * $canvas_tile_pad);
            my $h_num = $horiz_tile == 1 ? '' : sprintf($h_format, $j + 1);
            my( $ps_file_name );
            if ($horiz_tile == 1 and $vert_tile == 1) {
                $ps_file_name = "$file_root.ps";
            } else {
                my $join = ($v_num && $h_num) ? '-' : '';
                $ps_file_name = "$file_root-$h_num$join$v_num.ps";
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
    my( $self, $page_width ) = @_;
    
    if ($page_width) {
        confess "Illegal page width '$page_width'"
            unless $page_width =~ /^\d+$/;
        $self->{'_page_width'} = $page_width;
    }
    return $self->{'_page_width'}
        || 591; # A4 width in points
}

sub page_height {
    my( $self, $page_height ) = @_;
    
    if ($page_height) {
        confess "Illegal page height '$page_height'"
            unless $page_height =~ /^\d+$/;
        $self->{'_page_height'} = $page_height;
    }
    return $self->{'_page_height'}
        || 841; # A4 height in points
}

sub page_border {
    my( $self, $page_border ) = @_;
    
    if ($page_border) {
        confess "Illegal page border '$page_border'"
            unless $page_border =~ /^\d+$/;
        $self->{'_page_border'} = $page_border;
    }
    return $self->{'_page_border'}
        || 36; # half an inch in points
}

sub tile_overlap {
    my( $self, $tile_overlap ) = @_;
    
    if ($tile_overlap) {
        confess "Illegal page border '$tile_overlap'"
            unless $tile_overlap =~ /^\d+$/;
        $self->{'_tile_overlap'} = $tile_overlap;
    }
    return $self->{'_tile_overlap'}
        || ($self->page_border / 2);
}

sub landscape {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_print_landscape'} = $flag ? 1 : 0;
    }
    $flag = $self->{'_print_landscape'};
    return defined($flag) ? $flag : 0;
}


# Don't allow both horizontal and vertical tile to be set

sub horizontal_tile {
    my( $self, $count ) = @_;
    
    if ($count) {
        confess "Illegal horizontal tile count '$count'"
            unless $count =~ /^\d+$/;
        $self->{'_print_horizontal_tile'} = $count;
        $self->{'_print_vertical_tile'}   = 0;
    }
    return $self->{'_print_horizontal_tile'} || 0;
}

sub vertical_tile {
    my( $self, $count ) = @_;
    
    if ($count) {
        confess "Illegal vertical tile count '$count'"
            unless $count =~ /^\d+$/;
        $self->{'_print_horizontal_tile'} = 0;
        $self->{'_print_vertical_tile'}   = $count;
    }
    return $self->{'_print_vertical_tile'} || 0;
}


1;

__END__

=head1 NAME - CanvasWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

