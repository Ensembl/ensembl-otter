
### GenomeCanvas::Band::Plot

package GenomeCanvas::Band::Plot;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub height {
    my( $band, $height ) = @_;
    
    if ($height) {
        $band->{'_height'} = $height;
    }
    return $band->{'_height'} || 30;
}

sub range {
    my( $band, $low, $high ) = @_;
    
    if (defined $low) {
        confess "Invalid arguments"
            unless defined($high) and $low < $high;
        $band->{'_range'} = [$low,$high];
    }
    if (my $range = $band->{'_range'}) {
        return @$range;
    } else {
        return (0,1);
    }
}

sub render {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $rpp = $band->residues_per_pixel;
    my $seq_length = $vc->length;
    my $canvas = $band->canvas;
    my $y_offset = $band->y_offset;
    my @tags = $band->tags;
    
    my $height = $band->height;
    my $y_max = $y_offset + $height;
    
    # Draw grey boxes in plot where there is sequence missing
    $band->draw_sequence_gaps($y_offset);
    
    # Draw the plot where there is sequence
    {
        
        # Get the map of the chunks of sequence
        my @seq_coord = $band->sequence_chunk_coords;
        
        my $y_middle = $y_offset + ($height / 2);
        my $y_max = $band->y_max;
        my( $low, $high ) = $band->range;
        my $scale = $height / ($high - $low);
        for (my $i = 0; $i < @seq_coord; $i += 2) {
            my( $start, $end ) = @seq_coord[$i, $i+1];

            my( @plot );
            my( $pos, $value ) = $band->seqpos_value($start, $end);
            for (my $j = 0; $j < @$pos; $j++) {
                my $p = $pos->[$j];
                my $x = $p / $rpp;

                my $v = $value->[$j];
                my $y = $y_max - (($v - $low) * $scale);
                push(@plot, $x, $y);
            }
            
            # Draw midline
            my $x1 = $start / $rpp;
            my $x2 = $end   / $rpp;
            $canvas->createLine(
                $x1, $y_middle, $x2, $y_middle,
                -fill       => 'red',
                -width      => 1,
                -tags       => [@tags],
                );
            
            # Draw plot
            $canvas->createLine(
                @plot,
                -fill       => 'black',
                -width      => 1,
                #-smooth     => 1,
                -tags       => [@tags],
                );
        }
    }
    $band->draw_plot_axes;
    
    #my $seq_string = lc $vc->seq;
}

sub seqpos_value {
    my( $band, $start, $end ) = @_;
    
    my $rpp = $band->residues_per_pixel;
    
    my $vc = $band->virtual_contig;
    # Get the sequence for this chunk, and
    # check that it's the correct length.
    my $seq_length = $end - $start + 1;
    my $seq_str = $vc->subseq($start, $end);
    unless ($seq_length == length($seq_str)) {
        confess "subseq string is ", length($seq_str), " long, not $seq_length";
    }
    $seq_str = lc $seq_str;
    
    my( @pos, @value );
    my $tile_incr = $rpp * 5;
    my $tile_length = $tile_incr * 2;
    for (my $j = 0; $j < $seq_length; $j += $tile_incr) {
        my $tile_seq = substr($seq_str, $j, $tile_length);
        my $length = length($tile_seq);
        if ($length < $tile_length) {
            # Probably at the end of the sequence
            my $last_tile_seq = substr($seq_str, -1 * $tile_length, $tile_length);
            $length = length($last_tile_seq);
            if ($length == $tile_length) {
                my $gc_count = $last_tile_seq =~ tr/gc/gc/;
                my $gc_fraction = $gc_count / $length;
                push(@pos, $start + $seq_length - $tile_incr);
                push(@value, $gc_fraction);
            } else {
                warn "Didn't get full tile ($length != $tile_length)";
            }
        } else {
            my $gc_count = $tile_seq =~ tr/gc/gc/;
            my $gc_fraction = $gc_count / $length;
            push(@pos, $start + $j + $tile_incr);
            push(@value, $gc_fraction);
        }
    }
    
    return (\@pos, \@value);
}

sub x_major {
    my( $band, $x_major ) = @_;
    
    if ($x_major) {
        $band->{'_x_major'} = $x_major;
    }
    return $band->{'_x_major'} || 0.5;
}

sub draw_plot_axes {
    my( $band ) = @_;
    
    my $y_offset    = $band->y_offset;
    my $height      = $band->height;
    my $width       = $band->width;
    my @tags        = $band->tags;
    
    my $y_max = $y_offset + $height;
    my( $low, $high ) = $band->range;
    my $scale = $height / ($high - $low);
    my $major = $band->x_major;

    # X axis ticks
    for (my $i = $low; $i <= $high; $i += $major) {
        my $y = $y_max - (($i - $low) * $scale);
        # Left axis
        $band->tick_label($i, 'w', 0,      $y);
        # Right axis
        $band->tick_label($i, 'e', $width, $y);
    }
    
    # Scale along bottom of plot
    my $seq_length  = $band->virtual_contig->length;
    my $rpp = $band->residues_per_pixel;
    my $min_interval = $rpp * 50;   # Minumum space between labeled ticks
    my $interval = 1;
    my $multiplier = 5;
    while ($interval < $min_interval) {
        $interval *= $multiplier;
        $multiplier = ($multiplier == 5) ? 2 : 5;
    }
    my $precision = 7 - length($interval);
    #warn "interval = $interval, precision = $precision";
    for (my $i = 0; $i < $seq_length; $i += $interval) {
        my $Mbp = sprintf("%.${precision}f", $i / 1e6);
        $band->tick_label($Mbp, 's', $i / $rpp, $y_max);
    }

    # Rectangle in front of everything else
    my $canvas = $band->canvas;
    my $outline = $canvas->createRectangle(
        0, $y_offset, $width, $y_max,
        -fill       => undef,
        #-border     => 'black',
        -width      => 1,
        -tags       => [@tags],
        );
}

sub draw_sequence_gaps {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig;
    my $rpp = $band->residues_per_pixel;
    my $canvas = $band->canvas;
    my $height = $band->height;
    my $y_offset = $band->y_offset;
    my $y_max = $y_offset + $height;
    my @tags = $band->tags;
    
    my $prev_end = 0;
    foreach my $map_c ($vc->_vmap->each_MapContig) {
        my $start  = $map_c->start;
        my $end    = $map_c->end;
        my $gap = ($start - $prev_end - 1);
        if ($gap) {
            my $x1 = $prev_end / $rpp;
            my $x2 = ($start - 1) / $rpp;
            $canvas->createRectangle(
                $x1, $y_offset, $x2, $y_max,
                -fill       => 'grey',
                -outline    => undef,
                -tags       => [@tags],
                );
        }
        $prev_end = $end;
    }
    
}

sub sequence_chunk_coords {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig;
    # Make a map of the chunks of sequence
    my( @seq_coord );
    foreach my $map_c ($vc->_vmap->each_MapContig) {
        my $start  = $map_c->start;
        my $end    = $map_c->end;

        if (@seq_coord) {
            if ($seq_coord[$#seq_coord] == $start - 1) {
                $seq_coord[$#seq_coord] = $end;
            } else {
                push(@seq_coord, $start, $end);
            }
        } else {
            @seq_coord = ($start, $end);
        }
    }
    return @seq_coord;
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::Plot

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

