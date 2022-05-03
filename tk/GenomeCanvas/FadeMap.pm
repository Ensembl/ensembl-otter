=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::FadeMap

package GenomeCanvas::FadeMap;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub fade_color {
    my( $self, @color ) = @_;
    
    my( @rgb );
    if (@color == 1) {
        @rgb = $color[0] =~ /^#?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/
            or die "Illegal rgb parameter '$color[0]'\n";
        @rgb = map hex($_), @rgb;
    } else {
        @rgb = @color;
    }
    my( $hue, $sat, $lgt ) = $self->rgb_to_hsl(@rgb);
    my $n_steps = $self->number_of_steps;
    my( @fade_scale, @rgb_scale );
    for (my $i = 0; $i < $n_steps; $i++) {
        my $lgt_fade = $lgt + (((1 - $lgt) / $n_steps) * $i);
        my $sat_fade = $sat - (($sat / $n_steps) * $i);
        my @rgb = $self->hsl_to_rgb($hue, $sat_fade, $lgt_fade);
        push( @fade_scale, $self->rgb_to_web_hex(@rgb) );
        push( @rgb_scale, [map sprintf("%.0f", $_), @rgb] );
    }
    $self->{'_fade_scale'} = [reverse @fade_scale];
    $self->{'_rgb_scale'} = [reverse @rgb_scale];
}

sub rgb_to_web_hex {
    my( $self, @rgb ) = @_;
    
    my $hex = join('', map sprintf("%02x", $_), @rgb);
    return '#' . $hex;
}

sub rgb_scale {
    my( $self ) = @_;
    
    my $scale = $self->{'_rgb_scale'}
        or confess "No rgb scale found.  Call fade_color(COLOR) first";
    return @$scale;
}

sub get_color {
    my( $self, $i ) = @_;
    
    my $scale = $self->{'_fade_scale'}
        or confess "No color scale found.  Call fade_color(COLOR) first";
    return $scale->[$i];
}

sub number_of_steps {
    my( $self, $steps ) = @_;
    
    if ($steps) {
        $self->{'_number_of_steps'} = $steps;
    }
    return $self->{'_number_of_steps'} || 256;
}

sub rgb_to_hsl {
    my( $self, $r, $g, $b ) = @_;
    
    ($r,$g,$b) = map $_ / 0xff, ($r,$g,$b);
    
    # Calculate the lightness
    my($min, $max) = (1,0);
    foreach my $v ($r,$g,$b) {
        $min = $v if $v < $min;
        $max = $v if $v > $max;
    }
    #warn "max=$max min=$min";
    my $lgt = ($min + $max) / 2;
    
    my( $hue, $sat ) = (0,0);
    # If min and max are the same, then hue and
    # saturation stay at zero.  Otherwise:
    unless ($min == $max) {
        
        # Calculate the saturation
        if ($lgt < 0.5) {
            $sat = ($max - $min) / ($max + $min);
        } else {
            $sat = ($max - $min) / (2 - $max - $min);
        }
        
        # Calculate the hue
        my $divisor = $max - $min;
        if ($r == $max) {
            $hue =      ($g - $b) / $divisor;
        }
        elsif ($g == $max) {
            $hue = 2 + (($b - $r) / $divisor);
        }
        elsif ($b == $max) {
            $hue = 4 + (($r - $g) / $divisor);
        }
    }
    
    # return HSL
    return($hue, $sat, $lgt);
}

sub hsl_to_rgb {
    my( $self, $hue, $sat, $lgt ) = @_;
    
    $hue = $hue / 6;
    
    my($r,$g,$b) = (0,0,0);
    if ($sat == 0) {
        $r = $g = $b = $lgt;
    } else {
        my( $t1, $t2 );
        if ($lgt < 0.5) {
            $t2 = $lgt * ($sat + 1);
        } else {
            $t2 = $lgt + $sat - ($lgt * $sat);
        }
        $t1 = (2 * $lgt) - $t2;
        
        $r = $self->_temp_to_rgb_value($t1, $t2, $hue + (1/3));
        $g = $self->_temp_to_rgb_value($t1, $t2, $hue        );
        $b = $self->_temp_to_rgb_value($t1, $t2, $hue - (1/3));
    }
    
    return map $_ * 0xff, ($r,$g,$b);
}

sub _temp_to_rgb_value {
    my( $self, $t1, $t2, $t3 ) = @_;
    
    if ($t3 < 0) {
        $t3 += 1;
    }
    elsif ($t3 > 1) {
        $t3 -= 1;
    }
    
    my( $v );
    if (6 * $t3 < 1) {
        $v = $t1 + (($t2 - $t1) * 6 * $t3);
    }
    elsif (2 * $t3 < 1) {
        $v = $t2;
    }
    elsif (3 * $t3 < 2) {
        $v = $t1 + (($t2 - $t1) * ((2/3) - $t3) * 6);
    }
    else {
        $v = $t1;
    }
    
    return $v;
}



1;

__END__

=head1 NAME - GenomeCanvas::FadeMap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

