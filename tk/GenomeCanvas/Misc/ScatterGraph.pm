=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


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
        ['draw_circle', 'black',    undef],
        ['draw_circle', 'blue',     undef],
        ['draw_circle', 'red',      undef],
        );
    
    return $band;
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

sub draw_titles {
    my( $band ) = @_;
    
    my $y_offset    = $band->y_offset;
    my $canvas      = $band->canvas;
    my @tags        = $band->tags;
    my @bbox        = $band->band_bbox;
    my $axis_size   = $band->axis_size;
    my $font_size   = $band->font_size * 1.2;
    
    if (my $y_label = $band->y_axis_label) {
        my $x = $bbox[0] - $font_size;
        my $y = $y_offset + ($axis_size / 2);
        $band->canvas->createText(
            $x, $y,
            -text       => $y_label,
            -font       => ['helvetica', $font_size],
            -anchor     => 'e',
            -justify    => 'right',
            -tags       => [@tags],
            );
    }
    
    if (my $x_label = $band->x_axis_label) {
        my $x = $axis_size / 2;
        my $y = $bbox[3] + $font_size;
        $band->canvas->createText(
            $x, $y,
            -text       => $x_label,
            -font       => ['helvetica', $font_size],
            -anchor     => 'n',
            -justify    => 'center',
            -tags       => [@tags],
            );
    }
    
    my $x = $bbox[2]  + $font_size;
    my $y_begin = $y_offset + ($font_size * 2);
    my @styles = grep $_->[3], $band->y_series_styles;
    my $ele_size = $band->element_size;
    for (my $i = 0; $i < @styles; $i++) {
        my $s = $styles[$i];
        my( $draw_sub, $fill, $outline, $legend ) = @$s;
        my $y = $y_begin + ($i * $font_size * 2);
        $band->$draw_sub($x, $y, $fill, $outline);
        $band->tick_label($legend, 'e', $x + (2 * $ele_size), $y);
    }
}

sub render {
    my( $band ) = @_;
    
    my $y_offset    = $band->y_offset;
    my $canvas      = $band->canvas;
    my @tags        = $band->tags;
    
    my $axis_size   = $band->axis_size;
    
    # Work out max values on x and y axis
    my ($x_data, @y_data) = $band->x_y_data;
    my $x_max = $band->x_max || $band->max_value($x_data);
    my $y_max = $band->max_value(@y_data);
    my $x_scale = $axis_size / $x_max;
    my $y_scale = $axis_size / $y_max;
    
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
    
    # Label X axis
    my $x_tick_major = $band->x_tick_major;
    #my $magnitude = 10 ** int(log($x_tick_major) / log(10));
    my $magnitude = 10 ** 6;
    #warn "magnitude = $magnitude\n";
    for (my $n = 0; $n < $x_max; $n += $x_tick_major) {
        $band->tick_label($n / $magnitude, 's', $n * $x_scale, $y_offset + $axis_size);
    }
    
    # Label Y axis
    my $y_tick_major = $band->y_tick_major;
    for (my $n = 0; $n < $y_max; $n += $y_tick_major) {
        $band->tick_label($n, 'w', 0, $y_offset + $axis_size - ($n * $y_scale));
    }

    # Plot the data
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
            my $y = $y_offset + $axis_size - ($y_value * $y_scale);
                        
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

sub default_stle {
    return ['draw_diamond', undef, 'black'];
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

sub axis_size {
    my( $band, $axis_size ) = @_;
    
    if ($axis_size) {
        $band->{'_axis_size'} = $axis_size;
    }
    return $band->{'_axis_size'}
        || 4 * 72;  # Default 4 inches
}

sub x_max {
    my( $band, $x_max ) = @_;
    
    if ($x_max) {
        $band->{'_x_max'} = $x_max;
    }
    return $band->{'_x_max'} || 5 * (10 ** 6);
}

sub x_tick_major {
    my( $band, $x_tick_major ) = @_;
    
    if ($x_tick_major) {
        $band->{'_x_tick_major'} = $x_tick_major;
    }
    return $band->{'_x_tick_major'} || 5 * (10 ** 6);
}

sub y_tick_major {
    my( $band, $y_tick_major ) = @_;
    
    if ($y_tick_major) {
        $band->{'_y_tick_major'} = $y_tick_major;
    }
    return $band->{'_y_tick_major'} || 10;
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
    return $band->{'_element_size'} || 6;
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

