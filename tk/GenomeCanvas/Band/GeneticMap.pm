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


### GenomeCanvas::Band::GeneticMap

package GenomeCanvas::Band::GeneticMap;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub new {
    my( $pkg ) = @_;
    
    my $band = $pkg->SUPER::new;
    $band->title("Genetic\nmarkers");
    #$band->band_color('#4169e7');
    return $band;
}

sub render {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig;
    my $offset = $vc->chr_start - 1;
    my $length = $vc->length;
    
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    my $color     = $band->band_color;
    my @tags      = $band->tags;
    my $font_size = $band->font_size;
    
    my $triangle_height = $band->font_size;
    
    local *EPCR;
    my $file = $band->results_file
        or confess("results_file not set");
    open EPCR, $file or confess("Can't read '$file' : $!");
    my $nudge_distance = $font_size * 3;
    while (<EPCR>) {
	    /^\#/ and next; 
        my ($start, $end, $name_str) = (split)[3,4,8];
	    my ($name) = $name_str =~ /ID\=\"([^\"]+)\"/;
        my $pos = $start + (($end - $start) / 2) - $offset;
        next if $pos < 1;
        next if $pos > $length;
        
        my $x = $pos / $rpp;
        $canvas->createPolygon(
            $x, $y_offset - $triangle_height,
            $x + ($triangle_height / 2), $y_offset,
            $x - ($triangle_height / 2), $y_offset,
            -fill       => $color,
            -outline    => undef,
            -tags       => [@tags, $name],
            );
        my $label = $canvas->createText(
            $x, $y_offset + ($font_size / 4),
            -text => $name,
	    -font => ['helvetica', $font_size],
            -anchor => 'n',
            -tags => [@tags, $name],
            );
        my @bkgd = $canvas->bbox($name);
        my $bkgd_rectangle = $canvas->createRectangle(
            @bkgd,
            -outline    => '#cccccc',
            -width      => 2,
            -tags       => [@tags, 'genmap_bkgd_rec', $name],
            );
        $band->nudge_into_free_space($name, $nudge_distance)
    }
    $canvas->delete('genmap_bkgd_rec');
    close EPCR;
    
    my @bbox = $band->band_bbox;
    unless (@bbox) {
        $bbox[1] = $y_offset;
        $bbox[3] = $y_offset + $band->height;
    }
    $bbox[0] = 0;
    $bbox[2] = $band->width;
    $canvas->createRectangle(
        @bbox,
        -outline    => undef,
        -fill       => undef,
        -tags       => [@tags],
        );
}

sub results_file {
    my( $band, $file ) = @_;
    
    if ($file) {
        $band->{'_results_file'} = $file;
    }
    return $band->{'_results_file'};
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::GeneticMap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

