=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### KaryotypeWindow::Band

package KaryotypeWindow::Band;

use strict;
use warnings;
use Carp;
use KaryotypeWindow::Band::Centromere;
use KaryotypeWindow::Band::Stalk;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub is_rectangular {
    my( $self ) = @_;
    
    return $self->is_first || $self->is_last ? 0 : 1;
}


sub is_first {
    my( $self, $is_first ) = @_;
    
    if (defined $is_first) {
        $self->{'_is_first'} = $is_first;
    }
    return $self->{'_is_first'} || 0;
}

sub is_last {
    my( $self, $is_last ) = @_;
    
    if (defined $is_last) {
        $self->{'_is_last'} = $is_last;
    }
    return $self->{'_is_last'} || 0;
}

sub top_coordinates {
    my( $self ) = @_;
    
    if (my $coord = $self->{'_top_coordinates'}) {
        return @$coord;
    } else {
        confess "top_coordinates not set - not yet drawn?"; 
    }
}

sub right_coordinates {
    my( $self ) = @_;
    
    my @top = $self->top_coordinates;
    my @bot = $self->bottom_coordinates;
    
    # Want second half of @top then first half of @bottom
    return(
        @top[ (scalar(@top) / 2) .. $#top ],
        @bot[ 0 .. ((scalar(@bot) / 2) - 1)],
        );
}

sub left_coordinates {
    my( $self ) = @_;
    
    my @top = $self->top_coordinates;
    my @bot = $self->bottom_coordinates;
    
    # Want second half of @bot then first half of @top
    return(
        @bot[ (scalar(@bot) / 2) .. $#bot ],
        @top[ 0 .. ((scalar(@top) / 2) - 1)],
        );
}

sub set_top_coordinates {
    my( $self, @coord ) = @_;

    confess "Missing coordinates argument" unless @coord;
    $self->{'_top_coordinates'} = [@coord];

    return;
}

sub bottom_coordinates {
    my( $self ) = @_;
    
    if (my $coord = $self->{'_bottom_coordinates'}) {
        return @$coord;
    } else {
        confess "bottom_coordinates not set - not yet drawn?"; 
    }
}

sub set_bottom_coordinates {
    my( $self, @coord ) = @_;

    confess "Missing coordinates argument" unless @coord;
    $self->{'_bottom_coordinates'} = [@coord];

    return;
}

sub draw {
    my( $self, $chr, $kw, $x, $y ) = @_;
    
    my $scale = $kw->Mb_per_pixel;
    my $width = $chr->chr_width($kw);
    my $height = $self->height($kw);
    $self->set_top_coordinates(
        $x, $y,
        $x + $width, $y,
        );
    $self->set_bottom_coordinates(
        $x + $width, $y + $height,
        $x, $y + $height,
        );
    my @args = ();
    my $smooth_flag = $self->_round_top || $self->_round_bottom ? 1 : 0;
    
    $kw->canvas->createPolygon(
        $self->top_coordinates,
        $self->bottom_coordinates,
        -outline    => $self->outline || undef,
        -fill       => $self->fill    || undef,
        -smooth     => $smooth_flag,
        -stipple    => $self->stipple || '',
        );

    return;
}

# If the top is being rounded, we need to double
# up the bottom coordinates to keep a rectangular
# bottom to the band
sub _round_top {
    my( $self ) = @_;
    
    return 0 unless $self->is_first;
    my @bottom = $self->bottom_coordinates;
    my( @new );
    for (my $i = 0; $i < @bottom; $i += 2) {
        push(@new, @bottom[$i,$i+1, $i,$i+1]);
    }
    $self->set_bottom_coordinates(@new);
    return 1;
}

# If the bottom is being rounded, we need to double
# up the top coordinates to keep a rectangular
# top to the band
sub _round_bottom {
    my( $self ) = @_;
    
    return 0 unless $self->is_last;
    my @top = $self->top_coordinates;
    my( @new );
    for (my $i = 0; $i < @top; $i += 2) {
        push(@new, @top[$i,$i+1, $i,$i+1]);
    }
    $self->set_top_coordinates(@new);
    return 1;
}

sub set_fill_from_shade {
    my( $self, $shade ) = @_;
    
    confess "Missing shade argument" unless defined($shade);
    $shade = 255 - (255 * $shade);
    my $fill = sprintf "#%02x%02x%02x", $shade, $shade, $shade;
    $self->fill($fill);

    return;
}

sub fill {
    my( $self, $fill ) = @_;
    
    if ($fill) {
        $self->{'_fill'} = $fill;
    }
    return $self->{'_fill'};
}

sub stipple {
    my( $self, $stipple ) = @_;
    
    if (defined $stipple) {
        $self->{'_stipple'} = $stipple;
    }
    return $self->{'_stipple'};
}

sub outline {
    my( $self, $outline ) = @_;
    
    if ($outline) {
        $self->{'_outline'} = $outline;
    }
    return $self->{'_outline'};
}

sub height {
    my( $self, $kw ) = @_;
    
    return(
        ($self->length / 1_000_000)
        / $kw->Mb_per_pixel);
}

sub start {
    my( $self, $start ) = @_;
    
    if (defined $start) {
        $self->{'_start'} = $start;
    }
    return $self->{'_start'};
}

sub end {
    my( $self, $end ) = @_;
    
    if (defined $end) {
        $self->{'_end'} = $end;
    }
    return $self->{'_end'};
}

sub length {
    my( $self ) = @_;
    
    return $self->end - $self->start + 1;
}


1;

__END__

=head1 NAME - KaryotypeWindow::Band

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

