#### ChooserCanvas

## used as a base class for both AnaNotes.pm and HistoryPopup.pm
## both these classes take a sequence_chooser object and share common features based on this
package ChooserCanvas;

use strict;
use Carp;
#use Tk;
use GenomeCanvas::Band::SeqChooser;

use GenomeCanvas::State;
use CanvasWindow;

use vars qw{@ISA} ;
@ISA = ('CanvasWindow' , 'GenomeCanvas::State') ;

sub new {
    my ($pkg , $tk) = @_ ;
    my $gc = $pkg->SUPER::new($tk);
#    $gc->new_state;
    return $gc;
}

sub band_padding {
    my( $gc, $pixels ) = @_;
    
    if ($pixels) {
        $gc->{'_band_padding'} = $pixels;
    }
    return $gc->{'_band_padding'} || $gc->font_size * 2;
}

sub chooser_tag {
    my( $gc, $band, $tag ) = @_;
    
    confess "Missing argument: no band" unless $band;
    
    if ($tag) {
        $gc->{'_band_tag_map'}{$band} = $tag;
    }
    return $gc->{'_band_tag_map'}{$band};
}

sub deselect_all_selected_not_current {
    my( $self ) = @_;
    my $canvas = $self->canvas;
    $canvas->selectClear;
    foreach my $obj ($canvas->find('withtag', 'selected&&!current')) {
        $self->toggle_selection($canvas,  $obj);
    }
}


sub draw_chooser_outline {
    my( $gc, $band ) = @_;
    
    my $canvas = $gc->canvas;
    my @tags = $band->tags;

    my @rect = $canvas->bbox(@tags)
        #or confess "Can't get bbox for tags [@tags]";
        or warn "Nothing drawn for [@tags]" and return;
    my $r = $canvas->createRectangle(
        @rect,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );
    $canvas->lower($r, 'all');
}

sub get_unique_id {
    my($self ) = @_;
    my $canvas = $self->canvas ;
    my @rowID = map /^unique_id=(\d+)/ , $canvas->gettags('current');
    
    my $row_id = shift @rowID;
    return $row_id;
}
    
sub render {
    my( $gc ) = @_;

    
    $gc->clear_current_canvas;
    
    my $canvas = $gc->canvas;
   
    my $y_offset = 0;
    my $seq_chooser = $gc->sequence_chooser;
    my @map = $seq_chooser->chooser_map;
   
    #set tag for sequence_chooser object
#    $gc->{'_band_tag_map'}{$band} = "seq_chooser"
    $gc->chooser_tag($seq_chooser , "sequence_chooser");
    
    # Increase y_offset by the amount
    # given by band_padding
    $y_offset += $gc->band_padding;

    $gc->y_offset($y_offset);

    $seq_chooser->render;
    # Move the band to the correct position if it
    # drew itself somewhere else
    ##$gc->draw_chooser_outline($band);
    ##my $actual_y = ($canvas->bbox($tag))[1] || $y_offset;
    ##    if ($actual_y < $y_offset) {
    ##        my $y_move = $y_offset - $actual_y;
    ##        $canvas->move($tag, 0, $y_move);
    ##    }
    ##    $y_offset = ($canvas->bbox($tag))[3];
    ##    $gc->y_offset($y_offset);
    ##}
}

sub sequence_chooser{
    my ($self , $seq_chooser) = @_ ;
    if ($seq_chooser){
        $seq_chooser->canvas($self->canvas);
        $seq_chooser->add_State($self->state);
        $self->{'_seq_chooser'} = $seq_chooser ;
    }
    return $self-> {'_seq_chooser'};    
}

sub clear_current_canvas{
  
    my $self = shift @_;
    my $canvas = $self->canvas;  
    $canvas->delete("all"); 
      
}


sub toggle_current {
    my $self = shift @_; 
    
    my $canvas = $self->canvas;
    
    my $rowID = $self->get_unique_id();
    
    return unless defined ($rowID);
    my ($rec) = $canvas->find('withtag', "unique_id=$rowID&&contig_seq_rectangle");           

    $self->toggle_selection($canvas,  $rec);
   
}

sub toggle_selection {
    my ($self ,$canvas, $obj) =  @_;
    
    my $is_selected = grep $_ eq 'selected', $canvas->gettags($obj);
    
    my( $new_colour ); 
    if ($is_selected) {
        $new_colour = '#aaaaff';
        $canvas->dtag($obj, 'selected');
    } else {
        $new_colour = '#ffcccc';
        $canvas->addtag('selected', 'withtag', $obj);
    }
    $canvas->itemconfigure($obj,
        -fill => $new_colour,
        );
}



1;




