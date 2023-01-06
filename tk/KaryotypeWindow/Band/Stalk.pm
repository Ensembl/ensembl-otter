=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### KaryotypeWindow::Band::Stalk

package KaryotypeWindow::Band::Stalk;

use strict;
use warnings;
use Carp;
use base 'KaryotypeWindow::Band';


sub is_rectangular { return 0 };

sub draw {
    my( $self, $chr, $kw, $x, $y ) = @_;
    
    my $scale = $kw->Mb_per_pixel;
    my $width = $chr->chr_width($kw);
    my $height = $self->height($kw);
    my $name = $self->name;

    $self->set_stalk_coords($x, $y, $width, $height);
    
    $kw->canvas->createPolygon(
        $self->top_coordinates,
        $self->bottom_coordinates,
        -outline    => $self->outline || undef,
        -fill       => $self->fill    || undef,
        -smooth     => 1,
        -stipple    => $self->stipple,
        );

    return;
}

sub fill {
    my( $self, $fill ) = @_;
    
    if ($fill) {
        $self->{'_fill'} = $fill;
    }
    return $self->{'_fill'} || '#000000';
}

sub stipple {
    my( $self, $stipple ) = @_;
    
    if (defined $stipple) {
        $self->{'_stipple'} = $stipple;
    }
    return $self->{'_stipple'} || 'gvar';
}

sub set_stalk_coords {
    my( $self, $x, $y, $width, $height ) = @_;
    
    $self->set_top_coordinates(
        $x+(0.45*$width), $y+(0.5*$height),
        $x,$y, $x,$y, $x+$width,$y, $x+$width,$y,
        $x+(0.55*$width), $y+(0.5*$height),
        );
    $self->set_bottom_coordinates(
        $x+$width,$y+$height, $x+$width,$y+$height,
        $x,$y+$height, $x,$y+$height,
        );

    return;
}


1;

__END__

=head1 NAME - KaryotypeWindow::Band::Stalk

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

