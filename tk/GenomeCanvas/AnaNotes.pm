
### GenomeCanvas::AnaNotes

package GenomeCanvas::AnaNotes;

use strict;
use base 'GenomeCanvas';

##use GenomeCanvas;
##use vars '@ISA';
##@ISA = ('GenomeCanvas');

sub toggle_current {
    my ($self) = shift; 
    my $canvas = $self->canvas;
    
    my $ana_seq = get_current_ana_seq_id($canvas);
    return unless $ana_seq;
    
    my ($rec) = $canvas->find('withtag', "ana_seq_id=$ana_seq&&contig_seq_rectangle");        
    toggle_selection($canvas ,$rec);
}

sub get_current_ana_seq_id {
    my( $canvas ) = shift @_;
    
    my ($ana_seq) = map /^ana_seq_id=(\d+)/, $canvas->gettags('current');
    return $ana_seq;
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

sub deselect_all_selected_not_current {
    my( $self ) = @_;
    my $canvas = $self->canvas;
    $canvas->selectClear;
    foreach my $obj ($canvas->find('withtag', 'selected&&!current')) {
        toggle_selection($canvas,  $obj);
#        warn $obj->gettags;
    }
}





1;

__END__

=head1 NAME - GenomeCanvas::AnaNotes

=head1 AUTHOR

Colin Kingswood,,,, B<email> ck2@sanger.ac.uk

