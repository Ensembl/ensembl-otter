
### GenomeCanvas::AnaNotes::History

package GenomeCanvas::AnaNotes::History;

use strict;
use GenomeCanvas::AnaNotes;

use vars qw{@ISA};

@ISA = ('GenomeCanvas::AnaNotes');

sub toggle_current {
    my $self = shift @_; 
    my $canvas = $self->canvas;
    
    my $rowID = get_row_id($canvas);
    return unless defined ($rowID);
    my ($rec) = $canvas->find('withtag', "row_id=$rowID&&contig_seq_rectangle");           
    toggle_selection($canvas,  $rec);
   
}

sub get_row_id {
    my( $canvas ) = @_;
    my ($rowID) = map /^row_id=(\d+)/, $canvas->gettags('current');
    return $rowID;
}

sub deselect_all_selected_not_current {
    my( $self ) = @_;
    my $canvas = $self->canvas;
    $canvas->selectClear;
    foreach my $obj ($canvas->find('withtag', 'selected&&!current')) {
        toggle_selection($canvas,  $obj);
    }
}

sub toggle_selection {
    my ($canvas, $obj) =  @_;
    
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




1;

__END__

=head1 NAME - GenomeCanvas::AnaNotes::History

=head1 AUTHOR

Colin Kingswood,,,, B<email> ck2@sanger.ac.uk

