
### GenomeCanvas::Band::RepeatFeature

package GenomeCanvas::Band::RepeatFeature;

use strict;
use strict;
use Carp;
use GenomeCanvas::Band;
use GenomeCanvas::FadeMap;
use constant MAX_VC_LENGTH => 1000000;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub render {
    my( $band ) = @_;
    
    $band->draw_repeat_features;
    $band->draw_sequence_gaps;
}

sub draw_simple {
    my( $band, $flag ) = @_;
    
    if (defined $flag) {
        $band->{'_draw_simple'} = $flag ? 1 : 0;
    }
    return $band->{'_draw_simple'} || 0;
}

sub draw_repeat_features {
    my( $band ) = @_;
    
    my $big_vc = $band->virtual_contig;
    my $vc_length        = $big_vc->length;
    my $global_chr_start = $big_vc->_global_start;
    my $sgp_adapt        = $big_vc->dbobj->get_StaticGoldenPathAdaptor;
    my $chr_name         = $big_vc->_chr_name;
    
    for (my $i = 0; $i < $vc_length; $i += MAX_VC_LENGTH) {
        my $start = $i + 1;
        my $end   = $i + MAX_VC_LENGTH;
        warn "\nstart=$start\tend=$end\n";
        $end = $vc_length if $end > $vc_length;
        my $chr_start = $global_chr_start + $i;
        my $chr_end   = $global_chr_start + $end;
        warn "Drawing repeat features from $chr_start to $chr_end\n";
        my $vc = $sgp_adapt->fetch_VirtualContig_by_chr_start_end(
            $chr_name,
            $chr_start,
            $chr_end,
            );
        $band->draw_repeat_features_on_sub_vc($vc, $i);
    }
}

sub draw_repeat_features_on_sub_vc {
    my( $band, $vc, $offset ) = @_;

    # Sort all the repeat features by start and end and adjust
    # their coordinates, so we have an ordered list of non-
    # overlapping features.
    my $y1 = $band->y_offset;
    my $y2 = $y1 + $band->height;
    my $rpp = $band->residues_per_pixel;
    my $canvas = $band->canvas;
    my @tags = $band->tags;
    push(@tags, 'repeat');
    my @repeat = $vc->get_all_RepeatFeatures;
    @repeat = sort {$a->start <=> $b->start || $a->end <=> $b->end } @repeat;
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
    
    if ($band->draw_simple) {
        # Simple draw method:
        foreach my $feat (@repeat) {
            my $x1 = ($offset + $feat->start) / $rpp;
            my $x2 = ($offset + $feat->end  ) / $rpp;
            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -fill => '#6666ff',
                -outline => undef,
                -tags   => [@tags],
                );
        }
    } else {
        my $fademap = GenomeCanvas::FadeMap->new;
        $fademap->fade_color('#009900');

        my $vc_length = $vc->length;
        my $tile_count = int($vc_length / $rpp) + 1;
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
            
            my $x1 = ($offset + $start) / $rpp;
            my $x2 = ($offset + $end  ) / $rpp;
            $end = $vc_length if $vc_length < $end;
            #warn "$covered_length / ($end - $start + 1)\n";
            my $color = $fademap->get_color($covered_length / ($end - $start + 1));
            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -fill => $color,
                -outline => undef,
                -tags   => [@tags],
                );
        }
    }
}




1;

__END__

=head1 NAME - GenomeCanvas::Band::RepeatFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

