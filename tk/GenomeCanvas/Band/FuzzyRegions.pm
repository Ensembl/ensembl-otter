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


### GenomeCanvas::Band::FuzzyRegions

package GenomeCanvas::Band::FuzzyRegions;

use strict;
use Carp;
use base 'GenomeCanvas::Band';


sub height {
    my( $band, $height ) = @_;
    
    if ($height) {
        $band->{'_height'} = $height;
    }
    return $band->{'_height'} || $band->font_size * 6;
}

sub regions_file {
    my( $self, $regions_file ) = @_;
    
    if ($regions_file) {
        $self->{'_regions_file'} = $regions_file;
    }
    return $self->{'_regions_file'};
}

sub render {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $file = $band->regions_file
        or confess "regions_file not set";
    my $global_offset = $vc->chr_start - 1;

    open my $fh, $file or confess "Can't open '$file' : $!";

    my $height    = $band->height;
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    my @tags      = $band->tags;
    my $font_size = $band->font_size;
    
    $canvas->createRectangle(
        0, $y_offset, $band->width, $y_offset + $height,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );

    my $y1 = $y_offset + $font_size * 4;
    my $y2 = $y_offset + $font_size * 6;


    while (<$fh>) {
        next if /^\s*#/;
        next if /^\s*$/;
        
        my ($name, $start_err, $start, $end, $end_err, $colour, $arrow_end) = split;

        foreach ($start_err, $start, $end, $end_err) {
            $_ -= $global_offset;
        }

        my $middle = $start + (($end - $start) / 2);

        warn "Start End = $start\t$end\n";

	    next if $end_err < 1;
	    next if $start_err > $vc->length;
    
        foreach ($start_err, $start, $middle, $end, $end_err) {
            $_ /= $rpp;
        }

        # Coloured background
        $canvas->createRectangle(
            $start_err, $y1 + ($font_size / 2), $end_err, $y2 - ($font_size / 2),
            -fill       => $colour,
            -outline    => undef,
            -tags       => [@tags],
            );
        
        # Error bar lines
        foreach my $x ($start_err, $end_err) {
            $canvas->createLine(
                $x, $y1, $x, $y2,
                -fill       => 'black',
                -width      => 1,
                -tags       => [@tags],
                );
        }
        my $y_centre = $y1 + (($y2 - $y1) / 2);
        $canvas->createLine(
            $start_err, $y_centre, $end_err, $y_centre,
            -fill       => 'black',
            -width      => 1,
            -tags       => [@tags],
            -arrow      => $arrow_end,
            );
        
        # Rectangle in front of error bars
        $canvas->createRectangle(
            $start, $y1, $end, $y2,
            -fill       => $colour,
            -outline    => 'black',
            -width      => 1,
            -tags       => [@tags],
            );
        
        # Label above region
        $canvas->createText(
            $middle, $y1 - (2 * $font_size),
            -text   => $name,
            -fill   => 'black',
            -anchor => 'center',
            -font   => ['helvetica', 2 * $font_size, 'bold'],
            );
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::FuzzyRegions

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

