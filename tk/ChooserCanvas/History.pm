
### HistoryCanvas

package ChooserCanvas::History;

#use GenomeCanvas::AnaNotes;
use strict;
use ChooserCanvas;

use ChooserCanvas;
#use base GenomeCanvas;

use vars qw{@ISA};
@ISA = ('ChooserCanvas');




sub get_selected_row_id{
    my $self = shift @_ ;
    my $canvas = $self->canvas ;
    my @rowID = map /^unique_id=(\d+)/ , $canvas->gettags('selected');
    
    my $row_id = shift @rowID;
    return $row_id;
    
}  


sub confirm_update{
    my ($self , $mw) =  @_;
    
    my $confirm = $mw->messageBox(
                            -title      =>  "Warning!" ,
                            -message    =>  "This action will overwrite the selected entry. (Use the text entry field in the main window if you want to add a new comment)\nAre you sure you want to change this entry?", 
                            -type       =>  "OKCancel"   
                            );
    return $confirm;
}



1;
