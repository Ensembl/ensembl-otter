
### GenomeCanvas::MultiBand

package GenomeCanvas::Band::MultiBand;

use strict;
use Carp;
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

sub strip_colours {
    my( $band, @colours ) = @_;
    
    if (@colours) {
        $band->{'_strip_colours'} = [@colours];
    }
    if (my $l = $band->{'_strip_colours'}) {
        return @$l;
    } else {
        confess "no colours";
    }
}

sub strip_height {
    my( $band ) = @_;
    
    return $band->font_size;
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

sub draw_multi_segment {
    my ($band, $level, @feats) = @_;

    my $height    = $band->height;
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    # my $color     = $band->band_color;
    my @tags      = $band->tags;

    my ($y1, $y2) = @{($band->strip_y_map)[$level]};
    my ($color) = ($band->strip_colours)[$level];

    foreach my $f (@feats) {
	
	my $x1 = ($f->{'start'} - 1) / $rpp;
	my $x2 = ($f->{'end'} - 1)  / $rpp;

        $canvas->createRectangle(
	    $x1, $y1, $x2, $y2,
	    -fill       => $color,
	    -outline    => undef, #$color,
          #  -width      => 0.2,
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


    my ($global_y1, $global_y2) = ($strip_map[0]->[0], $strip_map[-1]->[1]);

    # Draw box around the whole strip
    $canvas->createLine(
	$x1, $global_y1 - $band->strip_padding, $x2, $global_y1 - $band->strip_padding,
	-fill       => 	'#000000',
	-width      =>  1,
	'-tags'     => [@tags],
    );

    $canvas->createLine(
	$x1, $global_y2 + $band->strip_padding, $x2, $global_y2 + $band->strip_padding,
	-fill       => 	'#000000',
	-width      => 1,
	'-tags'     => [@tags],
    );

    for (my $i = 0; $i < @strip_map; $i++) {
        my( $y1, $y2 ) = @{$strip_map[$i]};

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

=head1 NAME - GenomeCanvas::MultiBand

=head1 AUTHOR

Kevin Howe B<email> klh@sanger.ac.uk

