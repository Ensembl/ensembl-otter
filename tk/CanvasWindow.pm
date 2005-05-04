
### CanvasWindow

package CanvasWindow;

use strict;
use Carp;
use CanvasWindow::MainWindow;
use CanvasWindow::Utils 'expand_bbox';
use TransientWindow;
use TransientWindow::LogWindow;
use Tk::HeadedCanvas;

sub new {
    my( $pkg, $tk, $x, $y, $where_scrollbars, $canvas_class) = @_;
    
	if(!defined($where_scrollbars)) { # NB: not just empty, but undefined
		$where_scrollbars = 'se';
	}
	$canvas_class ||= 'Canvas';	# or 'HeadedCanvas', for example
    
    unless ($tk) {
        confess "Error usage: $pkg->new(<Tk::Widget object>)";
    }

    # Make new object and set-get initial canvas size
    my $self = bless {}, $pkg;
    ($x, $y) = $self->initial_canvas_size($x, $y);
    
    # Make and pack a canvas of the specified type

	my @creation_params = (
        -highlightthickness => 1,
        -background         => 'white',
        -width              => $x,
        -height             => $y,
	);
	my @packing_params = (
        -side => 'top',
        -fill => 'both',
        -expand => 1,
	);

	my $scrolled = $where_scrollbars
		? $tk->Scrolled( $canvas_class,
							-scrollbars => $where_scrollbars,
							@creation_params)
		: $tk->$canvas_class( @creation_params );

	$scrolled->pack( @packing_params );

	my $canvas = $where_scrollbars
		? $scrolled->Subwidget('canvas')
		: $scrolled;

    # Make a new CanvasWindow object, and return
    $self->canvas($canvas);
    $self->bind_scroll_commands;
    
    # Does the module define a Pixmap for the icon?
    if (my $pix = $pkg->icon_pixmap) {
        my $mw = $self->top_window();
        $mw->Icon(-image => $mw->Pixmap(-data => $pix));
    }
    
    return $self;
}

sub top_window {
	my $self = shift @_;

	return $self->canvas()->toplevel();
}

sub icon_pixmap {
    return;
}

sub initial_canvas_size {
    my( $self, $x, $y ) = @_;
    
    if ($x and $y) {
        $self->{'_initial_canvas_size'} = [$x, $y];
    }
    if (my $in = $self->{'_initial_canvas_size'}) {
        return @$in;
    } else {
        return (250,50); # Default
    }
}

sub canvas {
    my( $self, $canvas ) = @_;
    
    if ($canvas) {
        $self->{'_canvas'} = $canvas;
    }
    return $self->{'_canvas'};
}

# Default font and size for drawing on canvas

sub font {
    my( $self, $font ) = @_;
    
    if ($font) {
        $self->{'_font'} = $font;
        $self->{'_font_unit_width'} = undef;
    }
    return $self->{'_font'} || 'lucidatypewriter';
}

{
    my $_default_font_size = 15;

    sub font_size {
        my( $self, $font_size ) = @_;

        if ($font_size) {
            #$_default_font_size   = $font_size;
            $self->{'_font_size'} = $font_size;
            $self->{'_font_unit_width'} = undef;
        }
        return $self->{'_font_size'} || $_default_font_size;
    }
}

sub font_unit_width {
    my( $self ) = @_;
    
    my( $uw );
    unless ($uw = $self->{'_font_unit_width'}) {
        my $string_length = 1000;
        my $test_string = '0' x $string_length;
        my $font    = $self->font;
        my $size    = $self->font_size;
        my $width   = $self->canvas->fontMeasure(
            [$font, $size, 'normal'], $test_string);
        $uw = $width / $string_length;
        $self->{'_font_unit_width'} = $uw;
    }
    return $uw;
}

sub set_scroll_region {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my @bbox = $canvas->bbox('all');
    expand_bbox(\@bbox, 5);
    if (my @min_bbox = $self->minimum_scroll_bbox) {
        $bbox[0] = $min_bbox[0] if $min_bbox[0] < $bbox[0];
        $bbox[1] = $min_bbox[1] if $min_bbox[1] < $bbox[1];
        $bbox[2] = $min_bbox[2] if $min_bbox[2] > $bbox[2];
        $bbox[3] = $min_bbox[3] if $min_bbox[3] > $bbox[3];
    }
    
    my ($init_x, $init_y) = $self->initial_canvas_size;
    if (($bbox[2] - $bbox[0]) < $init_x) {
        $bbox[2] = $bbox[0] + $init_x;
    }
    if (($bbox[3] - $bbox[1]) < $init_y) {
        $bbox[3] = $bbox[1] + $init_y;
    }
    
    #warn "Setting scroll region to [@bbox]";
    $canvas->configure(
        -scrollregion => [@bbox],
        );
    return @bbox;
}

sub minimum_scroll_bbox {
    my( $self, @min_scroll ) = @_;
    
    if (@min_scroll) {
        my $count = @min_scroll;
        confess "Wrong number of coordinates '$count' not '4'"
            unless $count == 4;
        foreach my $i (@min_scroll) {
            confess("Non-integer value in: (",
                join(', ', map "'$_'", @min_scroll), ")")
                unless $i =~ /^-?\d+$/;
        }
        $self->{'_min_scroll_bbox'} = [@min_scroll];
    }
    if (my $m = $self->{'_min_scroll_bbox'}) {
        return @$m;
    } else {
        return;
    }
}

sub bind_scroll_commands {
    my( $self ) = @_;
    
    my $canvas = $self->canvas; # whether a self-managing or Scrolled

	my $scrolled = $canvas->can('Subwidget') # the owner of scrollbars
		? $canvas			# self-managing
		: $canvas->parent;	# Scrolled

    my $x_scroll = $scrolled->Subwidget('xscrollbar');
    my $y_scroll = $scrolled->Subwidget('yscrollbar');

	my $canvas_components = $canvas->can('canvases')
			? $canvas->canvases()
			: [ $canvas ];
    
    # Unbind the scrollbar keyboard events from the canvas
    my $class = ref($canvas);
    foreach my $sequence ($canvas->Tk::bind($class)) {
        if ($sequence =~ /Key/) {
            #print STDERR "seq=$sequence\n";
            $canvas->Tk::bind($class, $sequence, '');
        }
    }

    # Don't want the scrollbars to take keyboard focus
    foreach my $widget ($x_scroll, $y_scroll) {
        $widget->configure(
            -takefocus => 0,
            );
    }
    
    # ... Want canvas to do this instead
    $canvas->configure(
        -takefocus => 1,
        );
    $canvas->Tk::bind('<Enter>', sub{
        $canvas->Tk::focus;
        });
    
    # Home and End keys
    $canvas->Tk::bind('<Home>', sub{
        $y_scroll->ScrlToPos(0);
        });
    $canvas->Tk::bind('<End>', sub{
        $y_scroll->ScrlToPos(1);
        });
    
    # Page-Up and Page-Down keys
    $canvas->Tk::bind('<Next>', sub{
        $y_scroll->ScrlByPages('v', 1);
        });
    $canvas->Tk::bind('<Prior>', sub{
        $y_scroll->ScrlByPages('v', -1);
        });
    $canvas->Tk::bind('<Control-Down>', sub{
        $y_scroll->ScrlByPages('v', 1);
        });
    $canvas->Tk::bind('<Control-Up>', sub{
        $y_scroll->ScrlByPages('v', -1);
        });
    
    # Ctrl-Left and Ctrl-Right
    $canvas->Tk::bind('<Control-Left>', sub{
        $x_scroll->ScrlByPages('h', -1);
        });
    $canvas->Tk::bind('<Control-Right>', sub{
        $x_scroll->ScrlByPages('h', 1);
        });
    
    # Left and Right
    $canvas->Tk::bind('<Shift-Left>', sub{
        #warn "Shift-Left";
        $x_scroll->ScrlByUnits('h', -1);
        });
    $canvas->Tk::bind('<Shift-Right>', sub{
        #warn "Shift-Right";
        $x_scroll->ScrlByUnits('h', 1);
        });
    
    # Up and Down
    $canvas->Tk::bind('<Shift-Up>', sub{
        #warn "Shift-Up";
        $y_scroll->ScrlByUnits('v', -1);
        });
    $canvas->Tk::bind('<Shift-Down>', sub{
        #warn "Shift-Down";
        $y_scroll->ScrlByUnits('v', 1);
        });

	for my $cc (@$canvas_components) { # mousewheel must be bound on every focusable canvas component
		if($^O eq 'MSWin32'){
			#$cc->Tk::bind('<MouseWheel>',sub{
				#warn "Someone's scrolling with the mousewheel\n";
				#$y_scroll->ScrlByUnits('v', 3);
			#});
		}else{
				# vertical scroll
			$cc->Tk::bind('<4>', sub{
				# warn "Someone's scrolling up with the mousewheel\n";
				$y_scroll->ScrlByUnits('v', -3);
			});
			$cc->Tk::bind('<5>', sub{
				# warn "Someone's scrolling down with the mousewheel\n";
				$y_scroll->ScrlByUnits('v',  +3);
			});

				# horizontal scroll using Control modifier
			$cc->Tk::bind('<Control-4>', sub{
				# warn "Someone's scrolling left with the mousewheel\n";
				$x_scroll->ScrlByUnits('h', -3);
			});
			$cc->Tk::bind('<Control-5>', sub{
				# warn "Someone's scrolling right with the mousewheel\n";
				$x_scroll->ScrlByUnits('h',  +3);
			});
		}
	}
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

    my $margin = 10;
    
    confess "No object index given" unless $obj;
    my $canvas = $self->canvas;
    
    my $scroll_ref = $canvas->cget('scrollregion')
        or confess "No scrollregion";
    my ($scr_left,$scr_top,$scr_right,$scr_bottom) = @$scroll_ref;

# print "SCREGION: ".join(', ',($scr_left,$scr_top,$scr_right,$scr_bottom))."\n";

    my $width  = $scr_right  - $scr_left;
    my $height = $scr_bottom - $scr_top;
    #warn "width=$width, height=$height\n";

    my ($obj_left, $obj_top, $obj_right, $obj_bottom) = $canvas->bbox($obj);

# print "BBOX: ".join(', ',($obj_left, $obj_top, $obj_right, $obj_bottom))."\n";

    $obj_left   -= $scr_left;
    $obj_right  -= $scr_left;
    $obj_top    -= $scr_top;
    $obj_bottom -= $scr_top;
    
    my ($l_frac, $r_frac) = $canvas->xview;
    my $visible_left  = $width * $l_frac;
    my $visible_right = $width * $r_frac;
    #warn "left=$visible_left, right=$visible_right\n";
    if ($obj_right < $visible_left) {
        $canvas->xviewMoveto(($obj_left - $margin) / $width);
		# warn "scrolling left";
    }
    elsif ($obj_left > $visible_right) {
        my $visible_width = $visible_right - $visible_left;
        $canvas->xviewMoveto(($obj_right + $margin - $visible_width) / $width);
		# warn "scrolling right";
    }
    else {
        # warn "object is visible in x axis\n";
    }
    
    my ($t_frac, $b_frac) = $canvas->yview;
    my $visible_top  =   $height * $t_frac;
    my $visible_bottom = $height * $b_frac;
    #warn "top=$top, bottom=$bottom\n";
    if ($obj_bottom < $visible_top) {
        $canvas->yviewMoveto(($obj_top - $margin) / $height);
		# warn "scrolling up";
    }
    elsif ($obj_top > $visible_bottom) {
        my $visible_height = $visible_bottom - $visible_top;
        $canvas->yviewMoveto(($obj_bottom + $margin - $visible_height) / $height);
		# warn "scrolling down";
    } else {
        # warn "object is visible in y axis\n";
    }
}

sub fix_window_min_max_sizes {
    my( $self ) = @_;
    
    my $mw = $self->top_window();
    $mw->update;
    #$mw->withdraw;
    
    my( $max_x, $max_y, $display_max_x, $display_max_y )
        = $self->set_scroll_region_and_maxsize;
    
    # Get the current screen offsets
    my($x, $y) = $mw->geometry =~ /^=?\d+x\d+\+?(-?\d+)\+?(-?\d+)/;

    # Is there a set window size?
    if (my($fix_x, $fix_y) = $self->set_window_size) {
        $max_x = $fix_x;
        $max_y = $fix_y;
    } else {
        if (($x + $max_x) > $display_max_x) {
            $x = $display_max_x - $max_x;
        }
        if (($y + $max_y) > $display_max_y) {
            $y = $display_max_y - $max_y;
        }

        # Leave at least 100 pixels
        my $border = 100;
        if ($max_x > $display_max_x - $border) {
            $max_x = $display_max_x - $border;
        }
        if ($max_y > $display_max_y - $border) {
            $max_y = $display_max_y - $border;
        }
    }
    # Nudge the window onto the screen.
    $x = 0 if $x < 0;
    $y = 0 if $y < 0;

    my $geom = "${max_x}x$max_y+$x+$y";
    $mw->geometry($geom);
    #$mw->deiconify;
}

sub set_scroll_region_and_maxsize {
    my( $self ) = @_;

    my @bbox = $self->set_scroll_region;
    my $canvas_width  = $bbox[2] - $bbox[0];
    my $canvas_height = $bbox[3] - $bbox[1];
    
    my $mw = $self->top_window();
    
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

        my ($visible_x, $visible_y) = $self->visible_canvas_x_y;
        $other_x = int $width  - $visible_x;
        $other_y = int $height - $visible_y;

        ($display_max_x, $display_max_y) = $mw->maxsize;
        #warn "widget x = '$other_x'  widget y = '$other_y'\n";
        $self->{'_toplevel_other_max'} = [$other_x, $other_y, $display_max_x, $display_max_y];
        $mw->resizable(1,1);
    }

    my $max_x = $canvas_width  + $other_x;
    my $max_y = $canvas_height + $other_y;
    $max_x = $display_max_x if $max_x > $display_max_x;
    $max_y = $display_max_y if $max_y > $display_max_y;
    $mw->maxsize($max_x, $max_y);
    
    return($max_x, $max_y, $display_max_x, $display_max_y);
}

sub set_window_size {
    my( $self, $set_flag ) = @_;
    
    if ($set_flag) {
        my $mw = $self->top_window();
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
        $file_root = $self->top_window()->cget('title')
            || 'CanvasWindow';
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
    if ($page_width > $page_height) {
        confess "Page width must be greater than page height:\n",
            "  width = '$page_width', height = '$page_height'";
    }
    
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
        warn "print width = $print_width  print height = $print_height\n",
            "canvas width = $canvas_width  canvas height = $canvas_height\n";
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
    
    if (defined $count) {
        confess "Illegal horizontal tile count '$count'"
            unless $count =~ /^\d+$/;
        $self->{'_print_horizontal_tile'} = $count;
        $self->{'_print_vertical_tile'}   = 0;
    }
    return $self->{'_print_horizontal_tile'} || 0;
}

sub vertical_tile {
    my( $self, $count ) = @_;
    
    if (defined $count) {
        confess "Illegal vertical tile count '$count'"
            unless $count =~ /^\d+$/;
        $self->{'_print_horizontal_tile'} = 0;
        $self->{'_print_vertical_tile'}   = $count;
    }
    return $self->{'_print_vertical_tile'} || 0;
}

sub visible_canvas_bbox {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    
    my $scroll      = $canvas->cget('scrollregion');
    my ($xf1, $xf2) = $canvas->xview;
    my ($yf1, $yf2) = $canvas->yview;
    
    # Calculate corners of rectangle of visible area of canvas
    my $scroll_width  = $scroll->[2] - $scroll->[0];
    my $scroll_height = $scroll->[3] - $scroll->[1];

    my $x1 = ($xf1 * $scroll_width)  + $scroll->[0];
    my $x2 = ($xf2 * $scroll_width)  + $scroll->[0];

    my $y1 = ($yf1 * $scroll_height) + $scroll->[1];
    my $y2 = ($yf2 * $scroll_height) + $scroll->[1];
    
    return($x1, $y1, $x2, $y2);
}

sub visible_canvas_x_y {
    my( $self ) = @_;
    
    my @bbox = $self->visible_canvas_bbox;
    return( $bbox[2] - $bbox[0], $bbox[3] - $bbox[1] );
}

sub exception_message {
    my( $self, $except, @message ) = @_;
    
    # Take just the first line of the exception message
    my ($except_first) = $except =~ /^(.+)$/m;
    
    # Put the message on the terminal
    print STDERR $except;

    $self->message(@message, $except_first);
}

sub message {
    my( $self, @message ) = @_;
    
    my ($x1, $y1, $x2, $y2) = $self->visible_canvas_bbox;
    #warn "visible corners = ($x1, $y1, $x2, $y2)\n";
    
    # Width and height of visible area
    my $visible_width  = $x2 - $x1;
    my $visible_height = $y2 - $y1;
    
    # We have to make the message narrower if the
    # visible area of the canvas is smaller than
    # the desired message width.
    my $message_width = 200;
    my $smallest_width = 100;
    if ($visible_width < $message_width) {
        $message_width = $visible_width - 10;
        if ($message_width < $smallest_width) {
            $message_width = $smallest_width;
        }
    }
    
    # Calculate where to draw the text
    my $pad = 5;
    my $x_offset = int(($visible_width - $message_width) / 2);
    if ($x_offset < 0) {
        $x_offset = 0;
    }
    my $x = $x1 + $pad + $x_offset;
    my $y = $y1 + $pad + $pad;
    my $text_width = $message_width - ($pad * 2);
    
    return $self->message_at_x_y($x, $y, $text_width, @message);
}

sub message_at_x_y {
    my( $self, $x, $y, $text_width, @message ) = @_;

    confess "Bad message width '$text_width'"
        unless $text_width =~ /^[\.\d]+$/;
    my $pad = 5;

    # Print the message
    my $msg_id = 'message_id='. $self->next_message_id;
    my @tags = ('msg', $msg_id);
    my $canvas = $self->canvas;
    my $text = $canvas->createText(
        $x, $y,
        -anchor => 'nw',
        -text   => join("\n", @message),
        -width  => $text_width,
        -tags   => [@tags],
        );
    
    # Expand the bbox of the text
    my @bbox = $canvas->bbox($text);
    $bbox[0] -= $pad;
    $bbox[1] -= $pad;
    $bbox[2] += $pad;
    $bbox[3] += $pad;
    
    # Put a yellow rectangle under the text
    my $yellow_rec = $canvas->createRectangle(
        @bbox,
        -outline    => undef,
        -fill       => '#ffff66',
        -tags       => [@tags],
        );
    $canvas->lower($yellow_rec, $text);
    
    # Put a shadow under the yellow rectangle
    @bbox = map {$_ += 3} @bbox;
    my $grey_rec = $canvas->createRectangle(
        @bbox,
        -outline    => undef,
        -fill       => '#666666',
        -tags       => [@tags],
        );
    $canvas->lower($grey_rec, $yellow_rec);
    $canvas->update;
    
    $self->set_scroll_region_and_maxsize;
    return $msg_id;
}

sub delete_message {
    my( $self, $msg_id ) = @_;
    
    my $canvas = $self->canvas;
    unless ($msg_id) {
        my ($obj) = $canvas->find('withtag', 'current');
        if ($obj) {
            ($msg_id) = grep /^message_id=/, $canvas->gettags($obj);
        }
    }
    if ($msg_id) {
        $canvas->delete($msg_id);
        $self->set_scroll_region_and_maxsize;
        return 1;
    } else {
        return 0;
    }
}

sub next_message_id {
    my( $self ) = @_;
    
    return ++$self->{'_last_message_id'};
}

sub show_log{
    my $self = shift;

    my $tw = $self->{'__tw_log'};
    unless($tw){
        $tw = TransientWindow::LogWindow->new($self->top_window(), 'log file - ' . $self->name);
        $tw->initialise();
        $tw->draw();
        $self->{'__tw_log'} = $tw;
    }
    $tw->show_me();
}


{
    my $sel_tag = 'SelectedThing';

    sub highlight {
        my( $self, @obj ) = @_;

        my $canvas = $self->canvas;
        foreach my $o (@obj) {
            my @bbox = $canvas->bbox($o);
            $bbox[0] -= 1;
            $bbox[1] -= 1;
            $bbox[2] += 1;
            $bbox[3] += 1;
            my $r = $canvas->createRectangle(
                @bbox,
                -outline    => undef,
                -fill       => '#ffd700',
                -tags       => [$sel_tag],
                );
            $canvas->lower($r, $o);
            $self->add_selected($o, $r);
        }
    }

    sub re_highlight {
        my( $self, @obj ) = @_;

        my $canvas = $self->canvas;
        foreach my $o (@obj) {
            my $r = $self->{'_selected_list'}{$o}
                or confess "No highlight rectangle for object";
            my @bbox = $canvas->bbox($o);
            $bbox[0] -= 1;
            $bbox[1] -= 1;
            $bbox[2] += 1;
            $bbox[3] += 1;
            $canvas->coords($r, @bbox);
        }
    }

    sub deselect_all {
        my( $self ) = @_;

        my $canvas = $self->canvas;
        $canvas->delete($sel_tag);
        $self->{'_selected_list'} = undef;
    }

    sub add_selected {
        my( $self, $obj, $rect ) = @_;

        $self->{'_selected_list'}{$obj} = $rect;
    }

    sub remove_selected {
        my( $self, @obj ) = @_;

        my $canvas = $self->canvas;
        foreach my $o (@obj) {
            if (my $rect = $self->{'_selected_list'}{$o}) {
                $canvas->delete($rect);
                delete($self->{'_selected_list'}{$o});
            }
        }
    }

    sub is_selected {
        my( $self, $obj ) = @_;

        return $self->{'_selected_list'}{$obj} ? 1 : 0;
    }

    sub list_selected {
        my( $self ) = @_;

        if (my $sel = $self->{'_selected_list'}) {
            my @selected = sort {$a <=> $b} keys %$sel;
            return @selected;
        } else {
            return;
        }
    }

    sub count_selected {
        my( $self ) = @_;

        if (my $sel = $self->{'_selected_list'}) {
            return scalar keys %$sel;
        } else {
            return;
        }
    }
}

1;

__END__

=head1 NAME - CanvasWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

