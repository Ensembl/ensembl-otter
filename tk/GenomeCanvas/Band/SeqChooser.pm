
### GenomeCanvas::Band::SeqChooser

package GenomeCanvas::Band::SeqChooser;

use strict;
use Carp;
use GenomeCanvas::Band;
use CanvasWindow::Utils 'expand_bbox';

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub new {
    my( $pkg ) = @_;
    
    return bless {
        '_chooser_map'  => [],
        }, $pkg;
}

sub render {
    my( $band ) = @_;
    
    my $y_offset = $band->y_offset;
    my @x_offsets = $band->column_offsets;
    foreach my $row ($band->chooser_map) {
        #warn "$y_offset: [@$row]\n";
        if ($row->[0] =~ /^\d+$/) {
            $y_offset = $band->draw_seq_row($row, $y_offset, @x_offsets);
        } else {
            $y_offset = $band->draw_spacer($row, $y_offset);
        }
    }
}

sub x_padding {
    my( $band, $pad ) = @_;
    
    if (defined $pad) {
        $band->{'_x_padding'} = $pad;
    }
    return $band->{'_x_padding'} || 10;
}

sub max_width {
    my( $band, $width ) = @_;
    
    if (defined $width) {
        $band->{'_max_width'} = $width;
    }
    return $band->{'_max_width'} || 40 * $band->font_size;
}

sub draw_spacer {
    my( $band, $row, $y_offset ) = @_;
    
    my $name = "$row";
    my $canvas = $band->canvas;
    my $font_size = $band->font_size;
    my @tags = $band->tags;
    my $border = 3;
    my $y_space = 10;
    my $x1 = $border;
    my $y1 = $y_offset + $y_space;
    my $label = $canvas->createText(
        $x1, $y1,
        -text       => "@$row",
        -font       => ['helvetica', $font_size, 'bold'],
        -anchor     => 'nw',
        -tags       => [@tags, 'contig_gap', $name],
        );
    my @rect = $canvas->bbox($name);
    $rect[0] -= $border;
    $rect[2] += $border;
    $rect[3] += $y_space;
    my $outline = $canvas->createRectangle(
        @rect,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags, 'contig_gap', $name],
        );
    return $rect[3];
}

sub draw_seq_row {
    my( $band, $row, $y_offset, @x_offsets ) = @_;
    
    my ($id, @text) = @$row;
    $id = "ana_seq_id=$id";
    my $canvas = $band->canvas;
    my $font   = $band->column_font;
    my @tags   = $band->tags;
    my $width  = $band->max_width;
    push(@tags, $id, "sequence_name=$text[0]");
    my $y1 = $y_offset + 3;
    for (my $i = 0; $i < @text; $i++) {
        my $t = $text[$i] or next;
        my $label = $canvas->createText(
            $x_offsets[$i], $y1,
            -text       => $t,
            -font       => $font,
            -anchor     => 'nw',
            -width      => $width,
            -tags       => [@tags, 'contig_text'],
            );
    }
    my @rect = $canvas->bbox($id);
    $rect[0] = 0;
    $rect[2] = $x_offsets[$#x_offsets];
    expand_bbox(\@rect, 1);
    $rect[0] = 0;
    my $bkgd = $canvas->createRectangle(
        @rect,
        -fill       => '#ccccff',
        -outline    => undef,
        -tags       => [@tags, 'contig_seq_rectangle'],
        );
    $canvas->lower($bkgd, $id);
    return $rect[3];
}

sub chooser_map {
    my( $band, @map ) = @_;
    
    if (@map) {
        $band->{'_chooser_map'} = [@map];
    }
    return @{$band->{'_chooser_map'}};
}

sub column_font {
    my( $band ) = @_;
    
    return ['courier', $band->font_size];
}

sub column_offsets {
    my( $band ) = @_;
    
    #warn "Calculating column widths\n";
    my @widths = $band->column_widths;
    #warn "widths [@widths]\n";
    my $x_offset = $band->x_padding;
    my $column_gap = $x_offset * 2;
    my( @offsets ) = ($x_offset);
    for (my $i = 0; $i < @widths; $i++) {
        $x_offset += $widths[$i];
        push(@offsets, $x_offset);
        $x_offset += $column_gap;
    }
    
    #warn "offsets [@offsets]\n";
    
    return @offsets;
}

sub column_widths {
    my( $band ) = @_;
    
    # Get the longest ascii string for each column
    my(@longest);
    my(@widths);
    my $max = $band->max_width;
    foreach my $row ($band->chooser_map) {
        my( $id, @text ) = @$row;
        for (my $i = 0; $i < @text; $i++) {
            my $text = $text[$i] or next;
            my ($t_length) = length($text);
            if (my $l = $widths[$i]) {
                if ($t_length > $l) {
                    $widths[$i]  = $t_length;
                    $longest[$i] = $text;
                }
            } else {
                $widths[$i]  = $t_length;
                $longest[$i] = $text;
            }
        }
    }
    my $font = $band->column_font;
    my $canvas = $band->canvas;
    $max = $band->max_width;
    for (my $i = 0; $i < @widths; $i++) {
        my $text = substr($longest[$i], 0, $max) . 'XX';
        my $w = $canvas->fontMeasure($font, $text);
        $widths[$i] = ($w > $max) ? $max : $w;
    }
    
    return @widths;
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::SeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

