
### KaryotypeWindow::Band::Centromere

package KaryotypeWindow::Band::Centromere;

use strict;
use Carp;
use base 'KaryotypeWindow::Band';

sub is_rectangular { return 0 };

sub draw {
    my( $self, $chr, $canvas, $x, $y ) = @_;
    
    my $scale = $self->Mb_per_pixel;
    my $width = $chr->width;
    my $height = $self->height;
    my $name = $self->name;
    $self->set_top_coordinates(
        $name =~ /p/ ? $self->p_centromere($x, $y, $width, $height);
        );
    $self->set_bottom_coordinates(
        $x + $width, $y + $height,
        $x, $y + $height,
        );
    my @args = ();
    
    $canvas->createPolygon(
        $self->top_coordinates,
        $self->bottom_coordinates,
        -outline    => $self->outline || undef,
        -fill       => $self->fill    || undef,
        -smooth     => 1,
        );
}

sub p_centromere {
    my( $x, $y, $width, $height ) = @_;
    
    return (
        $x,$y, $x,$y, $x+$width,$y, $x+$width,$y,
        
        );
}

1;

__END__

=head1 NAME - KaryotypeWindow::Band::Centromere

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

