
### GenomeCanvas::Misc::ScatterGraph

package GenomeCanvas::Misc::ScatterGraph;

use strict;
use Carp;
use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub new {
    my( $pkg ) = @_;

    my $band = bless {}, $pkg;
    
    # sub, fill, outline
    $band->y_series_styles(
        ['draw_circle',  'black',    undef],
        ['draw_circle',    'blue',     undef],
        ['draw_circle',  'red',      undef],
        );
    
    return $band;
}


sub default_stle {
    return ['draw_diamond', undef, 'black'];
}


sub x_y_data {
    my( $band, @data ) = @_;
    
    if (@data) {
        foreach my $d (@data) {
            confess "Not an array ref '$d'"
                unless ref($d) eq 'ARRAY';
        }
        $band->{'_x_y_data'} = [@data];
    }
    my $data = $band->{'_x_y_data'}
        or confess "no data stored";
    return @$data;
}

sub render {
    my( $band ) = @_;
    
    my $y_offset    = $band->y_offset;
    my $canvas      = $band->canvas;
    my @tags        = $band->tags;
    
    my $axis_size = 72 * 4;     # 4 inches
    
    my @axis_pos = (
        0, $y_offset,
        $axis_size, $y_offset + $axis_size,
        );
    $canvas->createRectangle(
        @axis_pos,
        -fill       => undef,
        -outline    => 'black',
        -width      => 1,
        -tags       => [@tags],
        );
    
    # Work out max values on x and y axis
    my ($x_data, @y_data) = $band->x_y_data;
    my $max_x = $band->max_value($x_data);
    my $max_y = $band->max_value(@y_data);
    my $x_scale = $axis_size / $max_x;
    my $y_scale = $axis_size / $max_y;
    
    my @styles = $band->y_series_styles;
    for (my $s = 0; $s < @y_data; $s++) {
        my $series = $y_data[$s];
        my $style  = $styles[$s] || $band->default_style;
        my ($draw_sub, @fill_outline) = @$style;
        
        for (my $i = 0; $i < @$series; $i++) {
            my $x_value = $x_data->[$i];
            my $y_value = $series->[$i];
            next unless defined($y_value);
            
            my $x = $x_value * $x_scale;
            my $y = $axis_size - ($y_value * $y_scale);
                        
            $band->$draw_sub($x, $y, @fill_outline);
        }
    }
}

sub y_series_styles {
    my( $band, @styles ) = @_;
    
    if (@styles) {
        $band->{'_y_series_styles'} = [@styles];
    }
    my $styles = $band->{'_y_series_styles'}
        or confess "no y series styles";
    return @$styles;
}

sub max_value {
    my( $band, @arrays ) = @_;
    
    my( $max );
    foreach my $a (@arrays) {
        foreach my $v (@$a) {
            if (defined($max)) {
                if ($v > $max) {
                    $max = $v;
                }
            } else {
                $max = $v;
            }
        }
    }
    confess "no values" unless $max;
    return $max;
}

sub x_axis_label {
    my( $band, $x_axis_label ) = @_;
    
    if ($x_axis_label) {
        $band->{'_x_axis_label'} = $x_axis_label;
    }
    return $band->{'_x_axis_label'};
}

sub y_axis_label {
    my( $band, $y_axis_label ) = @_;
    
    if ($y_axis_label) {
        $band->{'_y_axis_label'} = $y_axis_label;
    }
    return $band->{'_y_axis_label'};
}

sub element_size {
    my( $band, $size ) = @_;
    
    if ($size) {
        $band->{'_element_size'} = $size;
    }
    return $band->{'_element_size'} || 4;
}

sub draw_diamond {
    my( $band, $x, $y, $fill, $outline ) = @_;
    
    if (! $fill and ! $outline) {
        $outline = 'black';
    }
    
    my $canvas = $band->canvas;
    my @tags   = $band->tags;
    my $side   = $band->element_size / 2;
    
    my @coords = (
        $x - $side, $y,
        $x, $y + $side,
        $x + $side, $y,
        $x, $y - $side,
        );
    $canvas->createPolygon(
        @coords,
        -fill       => $fill,
        -outline    => $outline,
        -width      => 0.5,
        -tags       => [@tags],
        );
}

sub draw_rectangle {
    my( $band, $x, $y, $fill, $outline ) = @_;
    
    if (! $fill and ! $outline) {
        $outline = 'black';
    }
    
    my $canvas = $band->canvas;
    my @tags   = $band->tags;
    my $side   = $band->element_size / 2;
    
    my @coords = (
        $x - $side, $y - $side,
        $x + $side, $y + $side,
        );
    $canvas->createRectangle(
        @coords,
        -fill       => $fill,
        -outline    => $outline,
        -width      => 0.5,
        -tags       => [@tags],
        );
}

sub draw_circle {
    my( $band, $x, $y, $fill, $outline ) = @_;
    
    if (! $fill and ! $outline) {
        $outline = 'black';
    }
    
    my $canvas = $band->canvas;
    my @tags   = $band->tags;
    my $side   = $band->element_size / 2;
    
    my @coords = (
        $x - $side, $y - $side,
        $x + $side, $y + $side,
        );
    $canvas->createOval(
        @coords,
        -fill       => $fill,
        -outline    => $outline,
        -width      => 0.5,
        -tags       => [@tags],
        );
}

1;

__END__

=head1 NAME - GenomeCanvas::Misc::ScatterGraph

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

