
### CanvasWindow::SequenceNotes::History

package CanvasWindow::SequenceNotes::History;

use strict;


use Carp;

use ChooserCanvas::HistoryCanvas;
use Bio::Otter::Lace::SequenceNote;
use GenomeCanvas::Band::SeqChooser;
{
    # new takes a mainwindow widget and creates a popup window, containg list of sequence notes
    sub new{
        my ($class , $mw ) =  @_;

        my $self = bless {} , $class;
        
        my $master_window = $mw->toplevel;  # returns the toplevel widget of the canvas
        my $new_toplevel = $master_window->Toplevel;   # creates a 'Toplevel' widget with parent 'master_window'
        $new_toplevel->title('Comment History');
        $self->toplevel($new_toplevel)  ;
        
        # create and add a history canavs object (with its own SeqChooser object)        
        my $history_canvas = ChooserCanvas::HistoryCanvas->new($new_toplevel); 
        my $chooser = GenomeCanvas::Band::SeqChooser->new ;
        $history_canvas->sequence_chooser($chooser);
        $self->history_canvas($history_canvas);
        
        my $string = '';
        $self->comment_string(\$string);
        

        
        
        # close only unmaps it from the display
        my $close_command = sub {$new_toplevel->withdraw };
        $new_toplevel->bind(     '<Control-w>' , $close_command);    
        $new_toplevel->bind(     '<Control-W>' , $close_command);    
        $new_toplevel->bind(     '<Escape>' , $close_command);

        my $canvas = $history_canvas->canvas;
        $canvas->configure(-selectbackground => 'gold');   

        #Make buttons inside a frame
        my $frame = $new_toplevel->Frame->pack(
                    -side => 'top',
                    );

        my $subFrame1 = $frame->Frame->pack(-side => 'top' );   # holds the text entry widget and the label
        my $subFrame2 = $frame->Frame->pack(-side => 'bottom',
                                            -expand => 1,
                                            -fill=> 'x'); # holds the other 4 buttons
                        
        # entry widget (and label) to type updated comment into
        $subFrame1->Label(
                    -text  => 'Note Text'
                        )->pack(-side => 'left')  ;
                
        my $comment_entry = $subFrame1->Entry(
                -width              => 55,
                -background         => 'white',
                -selectbackground   => 'gold',
                -textvariable       => $self->comment_string ,
                )->pack(
                        -side   => 'right',
                        -padx   => 4,
                        -fill   => 'x',
                        -anchor => 'ne'
                        );      
                        
        # button to retrieve previous clone to current one
        my $get_previous = sub{ $self->get_new_notes(-1)};
        my $previous_button = $subFrame2->Button(
                -text       =>  'Previous Clone' ,                     
                -command    =>  $get_previous 
            )->pack(-side => 'left',
                    -anchor => 'w');
        
        # button to retrieve next clone to current one
        my $get_next = sub{ $self->get_new_notes(+1)};
        my $next_button = $subFrame2->Button(
                -text       =>  'Next Clone' ,                     
                -command    =>  $get_next 
            )->pack(-side => 'left');            

     
        my $exit_button = $subFrame2->Button(
                    -text    =>  'Close' ,
                    -command =>  $close_command
                    )->pack(
                            -side   =>  'right' ,
                             );                     

        # subroutine to create button to update database and refresh remark history        
        my $update_button = $subFrame2->Button(
                    -text=> 'Update Comment',
                    -command => sub { 
                    #    if ($history_canvas->confirm_update($new_toplevel) eq 'Ok'){
                            my $next_comment  = $self->update_db_comment( $comment_entry->get());                              
                            ${$self->comment_string} = $next_comment ;
                            
                            $history_canvas->render;
                    #     }     
                    })->pack(
                             -side   => 'right',
                             -padx   => 4,
                             );


        # make canvas select / and deselect rows when clicked
        $canvas->CanvasBind('<Button-1>',
                sub {

                       # $self->deselect_all_selected_not_current();
                        $history_canvas->deselect_all_selected_not_current();
                       # $self->toggle_current();    
                        $history_canvas->toggle_current();  
                        # get id of currently selected row
                        my @list = $canvas->gettags('current'); 
                        my $id = $history_canvas->get_unique_id($canvas);
                       
                        my $hist_chooser = $self->hist_chooser;
                        my @choosermap = $hist_chooser->chooser_map;

                        # get comment from choosermap (choosermap is a 2 dimensional array)
                        ${$self->comment_string} = $choosermap[$id]->[$self->comment_index] ; 
                                                
                        $comment_entry->focusForce;
                        });
     
        
        return $self;
    }
#--------------------------------------------------------------------------------    
    # stores the reference for the string in the text entry widget
    sub comment_string(\$){
        my ($self , $string_ref) = @_ ;
    
        if ($string_ref){
            $self->{'_string_ref'} = $string_ref;

        }
        return $self->{'_string_ref'};
    }

#---------------------------------------------------------------------------------

    sub set_choosermap_indices{
        my ($self  , %hash ) =  @_ ;
        
        $self->ctg_id_index($hash{ctg_id});
        $self->comment_index($hash{comment});
        $self->time_index($hash{time});
    }     
    
    
    sub ctg_id_index{
        my ($self , $index) = @_;
        
        if ($index) {
            $self->{'_ctg_id_index'} = $index;    
        }
       
        return $self->{'_ctg_id_index'};
    }
    
    sub comment_index{
        my ($self , $index) = @_;
        
        if ($index) {
            $self->{'_comment_index'} = $index;    
        }
        return $self->{'_comment_index'};
    }
    
    sub time_index{
        my ($self , $index) = @_;
        
        if ($index) {
            $self->{'_time_index'} = $index;    
        }
        return $self->{'_time_index'};
    }
    

#----------------------------------------------------------------------------------

    sub toplevel{
        my ($self, $toplevel) = @_ ;

# should change this so that it checks the object type
        if ($toplevel){
            $self->{'_toplevel'} = $toplevel;
        }
        return $self->{'_toplevel'} ;
    }

#-----------------------------------------------------------------------------------
    sub get_CloneSequence_list_ref{
        my $self = shift; 
        my $ss = $self->sequence_set ;
        return $ss->CloneSequence_list;
    }


    sub get_current_CloneSequence{
        my $self = shift ;
                
        my $cs_list = $self->get_CloneSequence_list_ref;
#        warn $cs_list;    
        my $cs = @$cs_list->[$self->current_index || 0] ;
              
        return $cs;
    }

#-------------------------------------------------------------------------------------
    sub sequence_set{
        my ($self, $ss) = @_ ; 
        
        if ($ss){
            $self->{'_sequence_set'} = $ss ;
        }
        return $self->{'_sequence_set'}; 
    }
    
    sub DataSet{
        my ($self , $ds) = @_ ;
        
        if ($ds){
            $self->{'_dataset'} = $ds ;
        } 
        return $self->{'_dataset'};
    }
#-------------------------------------------------------------------------------------    
    
    sub history_canvas{
        my ($self , $history_canvas) = @_;

        if ($history_canvas){
            $self->{'_history_canvas'} = $history_canvas ; 
        }

        return $self->{'_history_canvas'};
    }

#---------------------------------------------------------------------------------------    
    
    sub hist_chooser{
        my ($self , $sequence_chooser ) = @_;
        
        my $hc = $self->history_canvas;
        if ($sequence_chooser){
            if ($hc){
                $hc->sequence_chooser($sequence_chooser);
            }else{
                carp "couldn't add sequence chooser object , as no GenomeCanvas::History object present"
            }
        }
        else{
            if ($hc){
                my @bl = $hc->sequence_chooser ;              
                $sequence_chooser = @bl->[0] ;   
            }
            else{
                carp "couldnt return sequence_chooser, as no genome canvas object";
            }
        }
        
    }    
 
#----------------------------------------------------------------------------------------
 
    sub display{
        my $self = shift @_;
        
        
        my $title = "Comment History for " . $self->get_current_CloneSequence->contig_name  ;
        $self->toplevel->title($title);
        my @map = $self->make_choosermap;
        my $hist_chooser = $self->hist_chooser;
        $hist_chooser->chooser_map(@map);
        my %tag_hash = ( 'unique_id=' => 0);
        $hist_chooser->chooser_tags( \%tag_hash);
        my @display_list = (1,2,4,5);                   # this is the list of elements in the chooser_map array that are to be displayed
        $hist_chooser->chooser_display_list(\@display_list);
        
        my $top = $self->toplevel;
        
        my $hist_canv = $self->history_canvas;
        $hist_canv->render;
        $hist_canv->fix_window_min_max_sizes;
         
        $top->deiconify;
        $top->raise;           
    }
    
    sub update_display{
        my $self = shift @_;
        
        my @map = $self->make_choosermap;
        $self->hist_chooser->chooser_map(@map);
        $self->history_canvas->render;
    }
#-----------------------------------------------------------------------------------------------------------------------------------    
    sub make_choosermap{
            
        my $self = shift @_;
        my @choosermap;
        
        my $cs = $self->get_current_CloneSequence;
        my $cs_notes = $cs->get_all_SequenceNotes ; 
                
  
        my $row_id = 0;
        foreach my $note  (@$cs_notes){
            my @row;
            # format time from unix to readable form
            my $time = $note->timestamp;
            my( $year, $month, $mday ) = (localtime($time))[5,4,3];
            my $time_txt = sprintf "%04d-%02d-%02d", 1900 + $year, 1 + $month, $mday;
            
            push @row , ("$row_id" , $cs->accession .'.' . $cs->sv , $note->author , $note->is_current, $time_txt, $note->text ); 
            push (@choosermap , [@row]);
            $row_id ++ ;
        }
          
        ## make this available as an argument for new method
        $self->set_choosermap_indices( comment => 5    ,
                            time    => 4    ,
                            ctg_id  => 1    ,
                            );  
        
        
        return @choosermap;    
    }

#----------------------------------------------------------------------------------------------------------------------------------    
    sub update_db_comment{
        
        my ( $self, $new_string ) = @_;      # new string to be updated     
        
        my $return_string = "" ;
        
        unless ($self->DataSet){
            warn "Dataset object has not been set for the history window.\nIt is not possible to update the comment unless this is set.";
            return;
        }
        
        $self->Busy;        
        my $clone_sequence = $self->get_current_CloneSequence ;
        
        my $history_canvas = $self->history_canvas;
        
        my $row_id = $history_canvas->get_selected_row_id();
        
        
       
        unless (defined $row_id ){
            warn "nothing selected to update ";
            $self->Unbusy;
            return $return_string;
        }
        
             
        my $current_note = @{$clone_sequence->get_all_SequenceNotes}->[$row_id];
        
              
        # check that author is valid to update note
        my $note_author = $current_note->author; 
        my $current_user= getlogin;

  
        if (($note_author eq $current_user )){     
            # confirm that the user wants to update the entry
            unless($history_canvas->confirm_update($self->toplevel)){
                return $return_string ;
            }
            $current_note->text($new_string); #change text

            my $contig_id = $clone_sequence->contig_id  || confess "no contig_id for this clone_sequence ";

            #$self->DataSet->update_Sequence_note($current_note , $contig_id);
            $clone_sequence->current_SequenceNote($current_note);
            $self->DataSet->update_current_SequenceNote($clone_sequence, $new_string);

            $self->update_display;
            
        }
        else{
            $self->toplevel->messageBox(-title => 'Sorry', 
            -message => "Only the origonal author, $note_author, can update these comments\nYou are currently logged on as $current_user", 
            -type => 'OK');
            #$return_string = "Sorry, only the original author can update this note"; 
            
        }
        $self->Unbusy;
        return $return_string;
    }
    
#----------------------------------------------------------------------------------------------------------------------------------    
    
    sub current_index{
        my ($self, $index) = @_ ;
        
        
        if (defined $index){    
            $self->{'_index'} = $index ;
        }
        
        return $self->{'_index'} ;
    }    
    
#-------------------------------------------------------------------------------------------------------------------------------    
    #  
    sub get_new_notes{
        my ($self , $int) = @_ ;
        
        my $current_index = $self->current_index;
        $current_index += $int ;
        
        ## check size of list of clones
        my $clone_list = $self->get_CloneSequence_list_ref; 
        
        if ($current_index < 0 || $current_index >= scalar(@$clone_list)){
            warn "would have gone off the end\n Size of array is.." . scalar(@$clone_list) . " index is at $current_index"  ;
        }
        else{
            $self->Busy;
#            warn "Current index is $current_index" ; 
            $self->current_index($current_index);
            #update choosermap and stuff here
            $self->display;
            $self->Unbusy;
        }
       
    }
#-------------------------------------------------------------------------------------------------------------------------

    sub Busy{   
        my $self= shift ;
        $self->toplevel->Busy;
    };
    
    sub Unbusy{ 
        my $self= shift;
        $self->toplevel->Unbusy;
    };
}
    


1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes::History

=head1 AUTHOR

Colin Kingswood,,,, B<email> ck2@sanger.ac.uk

=head1 Synopsis

    my $hp  = Bio::SequenceNotes::History->new($canv);
    $hp->sequence_set($self->SequenceSet );
    $hp->DataSet($self->SequenceSetChooser->DataSet);
    
    my $index = $self->current_CloneSequence_index();

    $hp->current_index($index);  
    $hp->display;
