
### GenomeCanvas::Band::RepeatFeature

package GenomeCanvas::Band::RepeatFeature;

use strict;
use strict;
use Carp;
use GD;
use GenomeCanvas::Band;
use GenomeCanvas::GD_StepMap;
use constant MAX_VC_LENGTH => 1000000;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub render {
    my( $band ) = @_;
    
    $band->draw_repeat_features;
    $band->draw_sequence_gaps;
    $band->draw_outline_and_labels;
}

sub draw_outline_and_labels {
    my( $band ) = @_;
    
    my $height      = $band->strip_height;
    my $canvas      = $band->canvas;
    my @classes     = $band->repeat_classes;
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
            -text       => $classes[$i],
            -anchor     => 'e',
            -justify    => 'right',
            -font       => ['helvetica', $font_size],
            '-tags'     => [@tags],
            );
        
        # Labels to the right of the strip
        $canvas->createText(
            $x2 + $text_offset, $text_y,
            -text       => $classes[$i],
            -anchor     => 'w',
            -justify    => 'left',
            -font       => ['helvetica', $font_size],
            '-tags'     => [@tags],
            );
    }
}

sub strip_y_map {
    my( $band ) = @_;
    
    my @classes     = $band->repeat_classes;
    my $y_offset    = $band->y_offset;
    my $height      = $band->strip_height;
    my $pad         = $band->strip_padding;
    my( @strip_map );
    for (my $i = 0; $i < @classes; $i++) {
        my $y1 = $y_offset + ($i * ($height + $pad));
        my $y2 = $y1 + $height;
        push(@strip_map, [$y1, $y2]);
    }
    return @strip_map;
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

sub draw_simple {
    my( $band, $flag ) = @_;
    
    if (defined $flag) {
        $band->{'_draw_simple'} = $flag ? 1 : 0;
    }
    return $band->{'_draw_simple'} || 0;
}

sub repeat_classes {
    my( $band, @classes ) = @_;
    
    if (@classes) {
        $band->{'_repeat_classes'} = [@classes];
    }
    if (my $c = $band->{'_repeat_classes'}) {
        @classes = @$c;
    } else {
        @classes = qw{ SINE LINE DNA LTR };
    }
    push(@classes, 'Other');
    return @classes;
}

sub repeat_classifier {
    my( $band, $sub ) = @_;
    
    if ($sub) {
        confess "Not a subroutine ref: '$sub'"
            unless ref($sub) eq 'CODE';
        $band->{'_repeat_classifer'} = $sub;
    }
    return $band->{'_repeat_classifer'} || confess "No repeat classifer";
}

sub draw_repeat_features {
    my( $band ) = @_;
    
    my $big_vc = $band->virtual_contig;
    my $vc_length        = $big_vc->length;
    my $global_chr_start = $big_vc->_global_start;
    my $sgp_adapt        = $big_vc->dbobj->get_StaticGoldenPathAdaptor;
    my $chr_name         = $big_vc->_chr_name;
    
    for (my $i = 0; $i < $vc_length; $i += MAX_VC_LENGTH) {
        my $end = $i + MAX_VC_LENGTH;
        my $last = 0;
        if ($end > $vc_length) {
            $end = $vc_length;
        }
        elsif (($vc_length - $end) < (MAX_VC_LENGTH / 10)) {
            $end = $vc_length;
            $last = 1;
        }
        my $chr_start = $global_chr_start + $i;
        my $chr_end   = $global_chr_start + $end - 1;
        #warn "Drawing repeat features from $chr_start to $chr_end\n";
        my $vc = $sgp_adapt->fetch_VirtualContig_by_chr_start_end(
            $chr_name,
            $chr_start,
            $chr_end,
            );
        $band->draw_repeat_features_on_sub_vc($vc, $i);
        $i = $vc_length if $last;
    }
}

sub draw_repeat_features_on_sub_vc {
    my( $band, $vc, $x_offset ) = @_;

    my $repeat_classifier = $band->repeat_classifier;
    my @class_list = $band->repeat_classes;
    my $other_class = $class_list[$#class_list];
    my %class = map {$_, []} @class_list;
    foreach my $r ($vc->get_all_RepeatFeatures) {
        my $c = &$repeat_classifier($band, $r->hseqname) || $other_class;
        push @{$class{$c}}, $r;
    }
    
    my $vc_length = $vc->length;
    for (my $i = 0; $i < @class_list; $i++) {
        my $c = $class_list[$i];
        $band->draw_repeat_class($x_offset, $i, $vc_length, $c, $class{$c});
    }
}

sub height {
    my( $band ) = @_;
    
    my $strip_count = $band->repeat_classes;
    my $s_height    = $band->strip_height;
    my $pad         = $band->strip_padding;
    my $height = ($strip_count * $band->strip_height) +
        (($strip_count - 1) * $band->strip_padding);
    return $height;
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

sub draw_repeat_class {
    my( $band, $x_offset, $level, $vc_length, $name, $repeat_list ) = @_;

    # Sort all the repeat features by start and end and adjust
    # their coordinates, so we have an ordered list of non-
    # overlapping features.
    my @repeat = sort {$a->start <=> $b->start || $a->end <=> $b->end } @$repeat_list;
    for (my $i = 1; $i < @repeat;) {
        my($prev, $this) = @repeat[$i - 1, $i];
        if ($prev->end >= $this->start) {
            my $new_this_start = $prev->end + 1;
            if ($new_this_start > $this->end) {
                # $prev engulfs $this
                warn "Removing engulfed repeat:\n",
                    $this->gff2_string, "\nWhich is engulfed by:\n",
                    $prev->gff2_string, "\n";
                splice(@repeat, $i, 1);
                next;   # Don't increment $i
            } else {
                # $prev only overlaps part of $this
                $this->start($new_this_start);
            }
        }
        $i++;
    }
    
    my $height = $band->strip_height;
    my $y1 = $band->y_offset + ($level * ($height + $band->strip_padding));
    my $y2 = $y1 + $height;
    my $rpp = $band->residues_per_pixel;
    my $canvas = $band->canvas;
    my @tags = $band->tags;

    my $tile_count = int($vc_length / $rpp);
    $tile_count += 1 if $vc_length % $rpp;
    my $stepmap = GenomeCanvas::GD_StepMap->new($tile_count, $height);
    $stepmap->color('#284d49');

    my( @values );
    for (my ($i,$j) = (0,0); $i < $tile_count; $i++) {
        my $start = $i * $rpp;
        my $end = $start + $rpp - 1;

        my $covered_length = 0;

        # Find the overlapping features
        my( @overlap );
        while (1) {
            my $r = $repeat[$j];
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

    # Add the gif to the image
    my $x = $x_offset / $rpp;

    my $gif = $stepmap->gif;
    my $tmp_img = "/tmp/RepeatFeature.$$.gif";
    local *GIF;
    open GIF, "> $tmp_img" or die;
    print GIF $gif;
    close GIF;
    my $image = $canvas->toplevel->Photo(
        '-format'   => 'gif',
        -file       => $tmp_img,
        );
    $canvas->createImage(
        $x, $y1 + 1,    # Off-by-1 error in placing images?
        -anchor     => 'nw',
        -image      => $image,
        -tags       => [@tags],
        );

    END {
        unlink($tmp_img) if $tmp_img;
    }
}




1;

__END__

=head1 NAME - GenomeCanvas::Band::RepeatFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

