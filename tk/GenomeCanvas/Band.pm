
### GenomeCanvas::Band

package GenomeCanvas::Band;

use strict;
use Carp;
use GenomeCanvas::State;

use vars '@ISA';
@ISA = ('GenomeCanvas::State');

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub tags {
    my( $band, @tags ) = @_;
    
    if (@tags) {
        $band->{'_tags'} = [@tags];
    }
    if (my $tags = $band->{'_tags'}) {
        return @$tags;
    } else {
        return;
    }
}

sub render {
    my( $band ) = @_;
    
    my $color = 'red';
    warn "GenomeCanvas::Band : Drawing default $color rectangle\n";

    my $canvas   = $band->canvas;
    my $y_offset = $band->y_offset;
    my @tags     = $band->tags;

    my @bbox = $canvas->bbox(@tags);
    my( $width );
    if (@bbox) {
        $width = $bbox[2] - $bbox[0];
    } else {
        $width = 600;
    }
    my @rect = (0, $y_offset, $width, $y_offset + 10);
    my $id = $canvas->createRectangle(
        @rect,
        -fill       => $color,
        -outline    => undef,
        '-tags'     => [@tags],
        );
}

sub tick_label {
    my( $band, $text, $dir, @line_start ) = @_;
    
    my @tags = $band->tags;
    confess "line_start array must have 2 elements" unless @line_start == 2;
    
    # Choose an appropriate size for the ticks
    my $font_size = $band->font_size;
    my $tick_length = $font_size / 3;
    $tick_length = 3 if $tick_length < 3;
    my $label_pad = $font_size / 4;
    $label_pad = 2 if $tick_length < 2;
    
    my( $anchor, $justify, @line_end, @text_start );
    if ($dir eq 'n') {
        $anchor = 's';
        $justify = 'center';
        @line_end = ($line_start[0], $line_start[1] - $tick_length);
        @text_start = ($line_end[0], $line_end[1]   - $label_pad);
    }
    elsif ($dir eq 'e') {
        $anchor = 'w';
        $justify = 'left';
        @line_end = ($line_start[0] + $tick_length, $line_start[1]);
        @text_start = ($line_end[0] + $label_pad,   $line_end[1]);
    }
    elsif ($dir eq 's') {
        $anchor = 'n';
        $justify = 'center';
        @line_end = ($line_start[0], $line_start[1] + $tick_length);
        @text_start = ($line_end[0], $line_end[1]   + $label_pad);
    }
    elsif ($dir eq 'w') {
        $anchor = 'e';
        $justify = 'right';
        @line_end = ($line_start[0] - $tick_length, $line_start[1]);
        @text_start = ($line_end[0] - $label_pad,   $line_end[1]);
    }
    else {
        confess "unknown direction '$dir'";
    }
    
    my $canvas = $band->canvas;
    $canvas->createLine(
        @line_start, @line_end,
        '-tags'     => [@tags],
        );
    $canvas->createText(
        @text_start,
        -text       => $text,
        -anchor     => $anchor,
        -justify    => $justify,
        -font       => ['helvetica', $band->font_size],
        '-tags'     => [@tags],
        );
}

sub virtual_contig {
    my( $band, $vc ) = @_;
    
    if ($vc) {
        confess "Not a Bio::EnsEMBL::Virtual::Contig : '$vc'"
            unless ref($vc) and $vc->isa('Bio::EnsEMBL::Virtual::Contig');
        $band->{'_virtual_contig'} = $vc;
    }
    return $band->{'_virtual_contig'};
}

sub nudge_into_free_space {
    my( $band, $tag_or_id, $y_inc ) = @_;
    
    confess "No tagOrId" unless $tag_or_id;
    $y_inc ||= 10;
    
    my $canvas = $band->canvas;
    my %self = map {$_, 1} $canvas->find('withtag', $tag_or_id);
    while (grep ! $self{$_}, $canvas->find('overlapping', $canvas->bbox($tag_or_id))) {
        $canvas->move($tag_or_id, 0, $y_inc);
    }
}

sub width {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $seq_length = $vc->length;
    my $rpp = $band->residues_per_pixel;
    return $seq_length / $rpp;
}

sub height {
    my( $band, $height ) = @_;
    
    if ($height) {
        $band->{'_height'} = $height;
    }
    return $band->{'_height'} || $band->font_size * 2;
}

sub y_max {
    my( $band ) = @_;
    
    my $y_offset = $band->y_offset;
    my $height = $band->height;
    return $y_offset + $height;
}

sub draw_sequence_gaps {
    my( $band ) = @_;
    
    my $canvas      = $band->canvas;
    my $height      = $band->height;
    my $rpp         = $band->residues_per_pixel;
    my $y_offset    = $band->y_offset;
    my $color       = $band->sequence_gap_color;
    my $y_max = $y_offset + $height;
    my @tags = $band->tags;

    # Draw the gaps    
    foreach my $gap ($band->sequence_gap_map) {
        my ($x1, $x2) = map $_ / $rpp, @$gap;
        $canvas->createRectangle(
            $x1, $y_offset, $x2, $y_max,
            -fill       => $color,
            -outline    => undef,
            '-tags'     => [@tags],
            );
    }
}

sub sequence_gap_color {    
    return '#ccbebe';
}

sub sequence_gap_map {
    my( $band ) = @_;

    my $vc = $band->virtual_contig;
    
    my( @gap_map );
    my $prev_end = 0;
    my @map_contig_list = $vc->_vmap->each_MapContig;
    for (my $i = 0; $i < @map_contig_list; $i++) {
        my $map_c = $map_contig_list[$i];
        my $start = $map_c->start;
        my $end   = $map_c->end;
        
        # Gap at the start?
        if ($i == 0 and $start > 1) {
            push(@gap_map, [1, $start - 1]);
        }
        
        # Gap after previous MapContig?
        my $gap = ($start - $prev_end - 1);
        if ($gap) {
            push(@gap_map, [$prev_end + 1, $start - 1]);
        }
        $prev_end = $end;
    }
    
    # Gap at end?
    my $vc_length = $vc->length;
    if ($prev_end < $vc_length) {
        push(@gap_map, [$prev_end + 1, $vc_length]);
    }
    
    return @gap_map;
}

sub sub_vc_size {
    my( $band, $size ) = @_;
    
    if ($size) {
        $band->{'sub_vc_size'} = $size;
    }
    return $band->{'sub_vc_size'} || 1e6;
}

sub next_sub_VirtualContig {
    my( $band ) = @_;
    
    my $big_vc = $band->virtual_contig;
    my $vc_length = $big_vc->length;
    my $i = $band->{'_sub_vc_offset'} || 0;
    if ($i >= $vc_length) {
        $band->{'_sub_vc_offset'} = undef;
        return;
    }
    
    my $global_chr_start = $big_vc->_global_start;
    my $sgp_adapt        = $big_vc->dbobj->get_StaticGoldenPathAdaptor;
    my $chr_name         = $big_vc->_chr_name;
    
    my $max_vc_length = $band->sub_vc_size;
    my $end = $i + $max_vc_length;
    
    my $last = 0;
    if ($end > $vc_length) {
        $end = $vc_length;
    }
    # Also extend to the end if the last vc would
    # be less than 10% of the max_vc_length
    elsif (($vc_length - $end) < ($max_vc_length / 10)) {
        $end = $vc_length;
        $last = 1;
    }

    # Record our position in the vc
    if ($last) {
        $band->{'_sub_vc_offset'} = $vc_length
    } else {
        $band->{'_sub_vc_offset'} += $max_vc_length;
    }

    my $chr_start = $global_chr_start + $i;
    my $chr_end   = $global_chr_start + $end - 1;
    #warn "Drawing repeat features from $chr_start to $chr_end\n";
    my $vc = $sgp_adapt->fetch_VirtualContig_by_chr_start_end(
        $chr_name,
        $chr_start,
        $chr_end,
        );

    return ($vc, $i);
}

sub merge_sort_Features {
    my $band = shift;
    
    my @feature = sort {$a->start <=> $b->start || $a->end <=> $b->end } @_;
    for (my $i = 1; $i < @feature;) {
        my($prev, $this) = @feature[$i - 1, $i];
        if ($prev->end >= $this->start) {
            my $new_this_start = $prev->end + 1;
            if ($new_this_start > $this->end) {
                # $prev engulfs $this
                warn "Removing engulfed feature:\n  ",
                    $this->gff2_string, "\n",
                    "Which is engulfed by:\n  ",
                    $prev->gff2_string, "\n";
                splice(@feature, $i, 1);
                next;   # Don't increment $i
            } else {
                # $prev only overlaps part of $this
                $this->start($new_this_start);
            }
        }
        $i++;
    }
    return @feature;
}


1;

__END__

=head1 NAME - GenomeCanvas::Band

=head1 DESCRIPTION

Base class for GenomeCanvas band objects.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

