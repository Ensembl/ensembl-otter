
package GenomeCanvas::Band::HistChooser ;

use strict;
use Carp;
use GenomeCanvas::Band::SeqChooser;
use CanvasWindow::Utils 'expand_bbox';

use vars '@ISA';
@ISA = ('GenomeCanvas::Band::SeqChooser');


sub render{
    my($band) = @_;
    
    warn "warning!" if my $y_offset = $band->y_offset;
    my @x_offsets = $band->column_offsets;

    foreach my $row ($band->chooser_map) {
        #warn "$y_offset: [@$row]\n";
 #       my $i =0;
#        if ($row->[0] =~ /^\d+$/) {

            $y_offset = $band->draw_seq_row($row, $y_offset, @x_offsets);
#        }else {
#           $y_offset = $band->draw_spacer($row, $y_offset);
#        }  
#        $i++ ;
    } 
}
sub draw_seq_row {
    my( $band, $row, $y_offset, @x_offsets ) = @_;
    
    my ($id, @text) = @$row;
    $id = "row_id=$id";
    my $canvas = $band->canvas;
    my $font   = $band->column_font;
    my @tags   = $band->tags;
    my $width  = $band->max_width; 
    push(@tags, $id);# , "sequence_name=$text[0]", "review_time=$text[1]" ,  "comment=$text[3]");
    #warn "@tags";
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


1;
