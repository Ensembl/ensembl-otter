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


### GenomeCanvas::DensityBand

package GenomeCanvas::DensityBand;

use strict;
use Carp;
use GenomeCanvas::FadeMap;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub height {
    my( $band ) = @_;
    
    my $strip_count = $band->strip_labels;
    my $s_height    = $band->strip_height;
    my $pad         = $band->strip_padding;
    my $height = ($strip_count * $band->strip_height) +
        (($strip_count - 1) * $band->strip_padding);
    return $height;
}

sub strip_labels {
    my( $band, @labels ) = @_;
    
    if (@labels) {
        $band->{'_strip_labels'} = [@labels];
    }
    if (my $l = $band->{'_strip_labels'}) {
        return @$l;
    } else {
        confess "no labels";
    }
}

sub strip_height {
    my( $band, $height ) = @_;
    
    if ($height) {
	    $band->{'_densband_strip_height'} = $height;
    }

    return $band->{'_densband_strip_height'} ||  $band->font_size * 2;
}

sub strip_padding {
    my( $band ) = @_;
    
    my $pad = int($band->strip_height / 5);
    $pad = 2 if $pad < 2;
    return $pad;
}

sub strip_y_map {
    my( $band ) = @_;
    
    my( $map );
    unless ($map = $band->{'_strip_y_map'}) {
        my $strip_count = scalar $band->strip_labels;
        my $y_offset    = $band->y_offset;
        my $height      = $band->strip_height;
        my $pad         = $band->strip_padding;
        #my $pad = 0;
        $map = [];
        for (my $i = 0; $i < $strip_count; $i++) {
            my $y1 = $y_offset + ($i * ($height + $pad));
            my $y2 = $y1 + $height;
            push(@$map, [$y1, $y2]);
        }
        $band->{'_strip_y_map'} = $map;
    }
    return @$map;
}

sub tile_pixels {
    my( $self, $tile_pixels ) = @_;
    
    if ($tile_pixels) {
        $self->{'_tile_pixels'} = $tile_pixels;
    }
    return $self->{'_tile_pixels'} || 2;
}

sub draw_sequence_gaps {
    my( $band ) = @_;
    
    my $canvas          = $band->canvas;
    my $height          = $band->height;
    my $rpp             = $band->residues_per_pixel;
    my $default_color   = $band->sequence_gap_color;
    my @tags = $band->tags;

    # Draw the gaps
    foreach my $gap ($band->sequence_gap_map) {
        my ($x1, $x2, $color) = @$gap;
        ($x1, $x2) = map $_ / $rpp, ($x1, $x2);
        $color ||= $default_color;
        
        # Over each strip
        foreach my $strip ($band->strip_y_map) {
            my( $y1, $y2 ) = @$strip;
            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -fill       => $color,
                -outline    => undef,
                '-tags'     => [@tags],
                );
        }
    }
}

sub draw_density_segment {
    my $band        = shift;
    my $x_offset    = shift;
    my $level       = shift;
    my $vc_length   = shift;

    # Sort all the feature features by start and end and adjust
    # their coordinates, so we have an ordered list of non-
    # overlapping features.
    my @feature = $band->merge_sort_Features(@_);
    
    my $height = $band->strip_height;
    my $y = ($band->strip_y_map)[$level];
    my $rpp = $band->residues_per_pixel;
    my $canvas = $band->canvas;
    my $tile_pixels = $band->tile_pixels;
    my $tile_width = $rpp * $tile_pixels;
    my @tags = $band->tags;
    
    my $tile_count = int($vc_length / $tile_width);
    $tile_count += 1 if $vc_length % $rpp;

    my( @values );
    for (my ($i,$j) = (0,0); $i < $tile_count; $i++) {
        my $start = $i * $tile_width;
        my $end = $start + $tile_width - 1;

        my $covered_length = 0;

        # Find the overlapping features
        my( @overlap );
        while (1) {
            my $r = $feature[$j];
            my( $r_start, $r_end );
            if ($r) {
                $r_start = $r->start;
                $r_end   = $r->end;
            }
            #warn "[$j]\tGoing to test ! ($r_end < $start or $r_start > $end)\n";
            my( $last_overlap );
            if ($r and
                ! ($r_end < $start or $r_start > $end)) {
                # The feature overlaps our range

                $r_start = $start if $r_start < $start;
                $r_end   = $end   if $r_end   > $end  ;
                $covered_length += $r_end - $r_start + 1;
                $last_overlap = $j;
            } else {
                # Put the pointer back to the last overlapping
                # feature, and exit the loop.
                $j = $last_overlap if defined $last_overlap;
                last;
            }
            $j++;
        }

        $end = $vc_length if $vc_length < $end;
        #warn "$covered_length / ($end - $start + 1)\n";
        push(@values, $covered_length / ($end - $start + 1));
    }

    my $fademap = GenomeCanvas::FadeMap->new;
    $fademap->fade_color($band->band_color);
    my ($y1, $y2) = ($y->[0], $y->[0] + $height);

    my ($min, $max) = (0,1);
    my $steps = $fademap->number_of_steps;
    for (my $i = 0; $i < @values; $i++) {
        my $val = $values[$i];
        my $x1 = ($x_offset / $rpp) + ($i * $tile_pixels);
        my $x2 = $x1 + $tile_pixels;
        
        # If the next box is going to be the same colour, just draw
        # the rectangle bigger. This draws far fewer boxes.
        for (my $j = $i + 1; $j < @values; $j++) {
            last unless $val == $values[$j];
            $x2 += $tile_pixels;
            $i = $j;
        }
        
        # Make sure the last box doesn't extend beyond the end
        # of the sequence.
        if ($i == $#values) {
            #printf STDERR "Resetting end coord from '$x2' to ";
            $x2 = ($x_offset / $rpp) + ($vc_length / $rpp);
            #printf STDERR "'$x2'\n";
        }
        
        my $color_i = $steps * (($val - $min) / ($max - $min));
        my $color = $fademap->get_color($color_i);
        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill       => $color,
            -outline    => undef,
            -tags       => [@tags],
            );
    }
}

sub draw_outline_and_labels {
    my( $band ) = @_;
    
    my $height      = $band->strip_height;
    my @labels      = $band->strip_labels;
    my $canvas      = $band->canvas;
    my @tags        = $band->tags;
    my $font_size   = $band->font_size;
    my $text_offset = $font_size / 2;
    my $x1 = 0;
    my $x2 = $band->virtual_contig->length / $band->residues_per_pixel;
    my @strip_map = $band->strip_y_map;
    for (my $i = 0; $i < @strip_map; $i++) {
        my( $y1, $y2 ) = @{$strip_map[$i]};
        
        # Draw box around the whole strip
        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill       => undef,
            -outline    => '#000000',
            '-tags'     => [@tags],
            );
        
        my $text_y = $y1 + ($height / 2);
        
        # Labels to the left of the strip
        $canvas->createText(
            -1 * $text_offset, $text_y,
            -text       => $labels[$i],
            -anchor     => 'e',
            -justify    => 'right',
            -font       => ['helvetica', $font_size],
            '-tags'     => [@tags],
            );
        
        # Labels to the right of the strip
        $canvas->createText(
            $x2 + $text_offset, $text_y,
            -text       => $labels[$i],
            -anchor     => 'w',
            -justify    => 'left',
            -font       => ['helvetica', $font_size],
            '-tags'     => [@tags],
            );
    }
}


1;

__END__

=head1 NAME - GenomeCanvas::DensityBand

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

