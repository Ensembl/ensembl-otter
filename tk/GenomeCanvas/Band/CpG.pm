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


### GenomeCanvas::Band::CpG

package GenomeCanvas::Band::CpG;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub new {
    my( $pkg ) = @_;
    
    my $band = $pkg->SUPER::new;
    $band->title('CpG islands');
    $band->band_color('#a620f7');
    return $band;
}

sub render {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";

    my $height    = $band->height;
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    my $color     = $band->band_color;
    my @tags      = $band->tags;
    
    $canvas->createRectangle(
        0, $y_offset, $band->width, $y_offset + $height,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );

    my $y1 = $y_offset + 1;
    my $y2 = $y_offset + $height - 1;
    foreach my $cpg (@{$vc->get_all_SimpleFeatures('CpG')}) {
        my $x1 = $cpg->start / $rpp;
        my $x2 = $cpg->end   / $rpp;
        
        $canvas->createRectangle(
            $x1, $y_offset, $x2, $y2,
            -fill       => $color,
            -outline    => $color,
            -width      => 0.5,
            -tags       => [@tags],
            );
    }
    
}




1;

__END__

=head1 NAME - GenomeCanvas::Band::CpG

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

