
### GenomeCanvas::Band::SeqChooser

package GenomeCanvas::Band::SeqChooser;

use strict;
use Carp;
use GenomeCanvas::Band;

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

sub draw_spacer {
    my( $band, $row, $y_offset ) = @_;
    
    my $name = "$row";
    my $canvas = $band->canvas;
    my $font_size = $band->font_size;
    my @tags = $band->tags;
    my $x1 = 0;
    my $y1 = $y_offset + 10;
    my $label = $canvas->createText(
        $x1, $y1,
        -text       => "@$row",
        -font       => ['helvetica', $font_size],
        -anchor     => 'nw',
        -tags       => [@tags, 'contig_gap', $name],
        );
    my @rect = $canvas->bbox($name);
    $band->expand_bbox(\@rect, 10);
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
    my $font_size = $band->font_size;
    my @tags = $band->tags;
    my $x1 = 3;
    my $y1 = $y_offset + 3;
    for (my $i = 0; $i < @text; $i++) {
        my $t = $text[$i] or next;
        my $label = $canvas->createText(
            ($x1 + $x_offsets[$i]), $y1,
            -text       => $t,
            -font       => ['courier', $font_size],
            -anchor     => 'nw',
            -tags       => [@tags, 'contig_gap', $id],
            );
    }
    my @rect = $canvas->bbox($id);
    $rect[2] = $x_offsets[$#x_offsets];
    $band->expand_bbox(\@rect, 1);
    $rect[0] = 0;
    my $bkgd = $canvas->createRectangle(
        @rect,
        -fill       => '#ccccff',
        -outline    => undef,
        -tags       => [@tags, 'contig_seq_rectangle', $id],
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

sub column_offsets {
    my( $band ) = @_;
    
    warn "Calculating column widths\n";
    my @widths = $band->column_widths;
    warn "widths [@widths]\n";
    my $column_gap = 10;
    my( @offsets ) = (0);
    my $x_offset = 0;
    for (my $i = 0; $i < @widths; $i++) {
        $x_offset += $widths[$i];
        push(@offsets, $x_offset);
        $x_offset += $column_gap;
    }
    
    warn "offsets [@offsets]\n";
    
    return @offsets;
}

sub cheap_column_widths {
    my( $band ) = @_;
    
    my(@widths);
    foreach my $row ($band->chooser_map) {
        my( $id, @text ) = @$row;
        for (my $i = 0; $i < @text; $i++) {
            my $text = $text[$i] or next;
            my $t_length = length($text);
            if (my $l = $widths[$i]) {
                $widths[$i] = $t_length if $t_length > $l;
            } else {
                $widths[$i] = $t_length;
            }
        }
    }
    foreach my $w (@widths) {
        if ($w) {
            my $text = 'N' x $w;
            ($w) = $band->text_size($text);
        } else {
            $w = 20;    # Empty columns
        }
    }
    return @widths;
}

sub column_widths {
    my( $band ) = @_;
    
    # Get the longest ascii string for each column
    my(@longest);
    my(@widths);
    foreach my $row ($band->chooser_map) {
        print STDERR ".";
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
    my $font_size = $band->font_size;
    foreach my $i (@widths) {
        $i *= $font_size;
    }
    return @widths;
    
    print STDERR "\nlongest = [@longest]\n";
    
    # Calculate the actual width in pixels for each
    # of the longest strings.
    my $canvas = $band->canvas;
    for (my $i = 0; $i < @longest; $i++) {
        my $text = $longest[$i] .'XX';
        warn "Measuring '$text'";
        $widths[$i] = $band->text_width($text);
    }
    return @widths;
}

sub text_width {
    my( $band, $text ) = @_;
    
    print STDERR "Making text object ...";
    my $canvas = $band->canvas;
    my $font_size = $band->font_size;
    my $t = $canvas->createText(
        0,0,
        -text       => $text,
        -font       => ['helvetica', $font_size],
        -anchor     => 'nw',
        );
    print STDERR " done";
    my @bbox = $canvas->bbox($t);
    $canvas->delete($t);
    return ($bbox[2] - $bbox[0]);
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::SeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

