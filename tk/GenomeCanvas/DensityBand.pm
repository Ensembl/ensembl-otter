
### GenomeCanvas::DensityBand

package GenomeCanvas::DensityBand;

use strict;
use Carp;
use GenomeCanvas::GD_StepMap;
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
    my( $band ) = @_;
    
    return $band->font_size * 2;
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

sub draw_sequence_gaps {
    my( $band ) = @_;
    
    my $canvas      = $band->canvas;
    my $height      = $band->height;
    my $rpp         = $band->residues_per_pixel;
    my $color       = $band->sequence_gap_color;
    my @tags = $band->tags;

    # Draw the gaps
    foreach my $gap ($band->sequence_gap_map) {
        my ($x1, $x2) = map $_ / $rpp, @$gap;
        
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
    my @tags = $band->tags;

    my $tile_count = int($vc_length / $rpp);
    $tile_count += 1 if $vc_length % $rpp;
    my $stepmap = GenomeCanvas::GD_StepMap->new($tile_count, $height);
    $stepmap->color($band->band_color);

    my( @values );
    for (my ($i,$j) = (0,0); $i < $tile_count; $i++) {
        my $start = $i * $rpp;
        my $end = $start + $rpp - 1;

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
    $stepmap->values(@values);

    # Print the GIF to a temporary file
    #my $tmp_img = "/tmp/DensityBand.$$.gif";
    my $tmp_img = "DensityBand.$$.gif";
    local *GIF;
    open GIF, "> $tmp_img" or die;
    print GIF $stepmap->gif;
    close GIF;
    die $tmp_img;
    END {
        #unlink($tmp_img) if $tmp_img;
    }

    # Add the gif to the image
    my $x = $x_offset / $rpp;
    my $image = $canvas->Photo(
        '-format'   => 'gif',
        -file       => $tmp_img,
        );
    $canvas->createImage(
        $x, $y->[0] + 0.5,    # Off-by-1 error when placing images?
        -anchor     => 'nw',
        -image      => $image,
        -tags       => [@tags],
        );

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

