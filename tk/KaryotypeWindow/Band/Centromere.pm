
### KaryotypeWindow::Band::Centromere

package KaryotypeWindow::Band::Centromere;

use strict;
use Carp;
use base 'KaryotypeWindow::Band';

sub is_rectangular { return 0 };

sub draw {
    my( $self, $chr, $canvas, $x, $y ) = @_;
    
    warn "drawing a centromere";
    
    my $scale = $self->Mb_per_pixel;
    my $width = $chr->width;
    my $height = $self->height;
    my $name = $self->name;

    if ($name =~ /p/) {
        $self->set_p_centromere_coords($x, $y, $width, $height);
    } else {
        $self->set_q_centromere_coords($x, $y, $width, $height);
    }
    
    $canvas->createPolygon(
        $self->top_coordinates,
        $self->bottom_coordinates,
        -outline    => $self->outline || undef,
        -fill       => $self->fill    || undef,
        -smooth     => 1,
        );
}

sub fill { return '#ffffff' }

sub set_p_centromere_coords {
    my( $self, $x, $y, $width, $height ) = @_;
    
    $self->set_top_coordinates(
        $x,$y, $x,$y, $x+$width,$y, $x+$width,$y,
        );
    $self->set_bottom_coordinates(
        $x+$width,$y+(0.5*$height), $x+(0.75*$width),$y+(0.5*$height),
        $x+(0.75*$width),$y+$height, $x+(0.75*$width),$y+$height,
        $x+(0.25*$width),$y+$height, $x+(0.25*$width),$y+$height,
        $x+(0.25*$width),$y+(0.5*$height), $x,$y+(0.5*$height),
        );
}

sub set_q_centromere_coords {
    my( $self, $x, $y, $width, $height ) = @_;
    
    $self->set_top_coordinates(
        $x,$y+(0.5*$height), $x+(0.25*$width),$y+(0.5*$height),
        $x+(0.25*$width),$y, $x+(0.25*$width),$y,
        $x+(0.75*$width),$y, $x+(0.75*$width),$y,
        $x+(0.75*$width),$y+(0.5*$height),  $x+$width,$y+(0.5*$height),
        );
    $self->set_bottom_coordinates(
        $x+$width,$y+$height,               $x+$width,$y+$height,
        $x,$y+$height,                      $x,$y+$height,
        );
}

1;

__END__

=head1 NAME - KaryotypeWindow::Band::Centromere

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

