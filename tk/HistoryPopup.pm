## HistoryPopup
## perl object for the history popup window in ana_notes
package HistoryPopup;

use strict;
use Carp;
use Tk;
use ChooserCanvas::History;
use Bio::EnsEMBL::Pipeline::AnaSubmission qw{ set_db_args sub_db prepare_statement get_db}  ;


{
    sub new{
        my ($class , $choosermap_variables  ) = @_;

        my $self = bless {} , $class;
        
        if ($choosermap_variables){
            $self->set_choosermap_variables(1, 3 , 5);
            
        }else{
            ## default values - work for the choosermap used at time of writing
            $self->set_choosermap_variables(1, 3 , 5);     
        }
        return $self;
    }

    # next subroutine sets the index positions for variables in each row the choosermap
    ## so that for each row of the chooser_map @row->[$self->ctg_id_index]  will contain the contig_id variable
    sub set_choosermap_variables{
        my ($self , $ctg_id , $time , $comment) = @_;
               
        $self->ctg_id_index($ctg_id);   
        $self->time_index($time);
        $self->comment_index($comment);
    }

    sub history_canvas{
        my ($self , $history_canvas) = @_;

        if ($history_canvas){
            $self->{'_history_canvas'} = $history_canvas ; 
        }

        return $self->{'_history_canvas'};
    }
    
    sub canvas{
        my ($self ) = shift @_;
        return $self->history_canvas->canvas;
    }


    sub toplevel{
        my ($self, $toplevel) = @_ ;

        if ($toplevel){
            $self->{'_toplevel'} = $toplevel;
        }
        return $self->{'_toplevel'} ;
    }

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

    ##sub comment_string{
    ##    my ($self , $string_ref) = @_;

        ##if ($string_ref){
        ##    $self->{'_comment_string'} = $string_ref;
        ##}
       
        ##return $self->{'_comment_string'} ;

    ##};


my $comment_string ; # used as a variable for the text entry widget

    sub make_popup{
        my ($self , $mw_canvas , $asid) = @_ ;

        my  $hist_canvas; # ChooserCanvas::History object; 
        my  $hist_chooser ; # sequence_chooser object



        $comment_string = ''; 
        # make toplevel object which is transient of master
        my $master = $mw_canvas->toplevel ;
        my $top = $master->Toplevel;
        $top->transient($master);

       

        $hist_canvas = ChooserCanvas::History->new($top) ;
        
        $hist_chooser =  GenomeCanvas::Band::SeqChooser->new ;
        
        $hist_canvas->sequence_chooser($hist_chooser);
        $self->history_canvas($hist_canvas);

        # close only unmaps it from the display
        my $close_command = sub {$top->withdraw };

        $top->bind(     '<Control-w>' , $close_command);    
        $top->bind(     '<Control-W>' , $close_command);    
        $top->bind(     '<Escape>' , $close_command);

        my $canvas = $hist_canvas->canvas;
        $canvas->configure(-selectbackground => 'gold');   


        #Make buttons inside a frame
        my $frame = $top->Frame->pack(
                    -side => 'top',
                    );

        my $exit_button = $frame->Button(
                    -text    =>  'Close' ,
                    -command =>  $close_command
                    )->pack(
                            -side   =>  'left' ,
                            );

        $frame->Label(
                    -text  => 'Note Text'
                        )->pack(-side => 'left' )  ;


        # entry widget to type updated comment into
        my $comment_entry = $frame->Entry(
                    -width              => 55,
                    -background         => 'white',
                    -selectbackground   => 'gold',
                    -textvariable       => \$comment_string ,
                    )->pack(
                            -side   => 'left',
                            -padx   => 4,
                            -fill   => 'x',
                            );      

        # subroutine to create button to update database and refresh remark history        
        my $update_button = $frame->Button(
                    -text=> 'Update Comment',
                    -command => sub { 
                        if ($hist_canvas->confirm_update($top) eq 'Ok'){
                            $self->update_db_comment( $comment_entry->get());                              
                            $comment_string = "";
                            
                            $hist_canvas->render;
                         }     
                    })->pack(
                             -side   => 'left',
                             -padx   => 4,
                             );


        # make canvas select / and deselect rows when clicked
        $canvas->CanvasBind('<Button-1>',
                sub {

                       # $self->deselect_all_selected_not_current();
                        $hist_canvas->deselect_all_selected_not_current();
                       # $self->toggle_current();    
                        $hist_canvas->toggle_current();  
                        # get id of currently selected row
                        my @list = $canvas->gettags('current'); 
                        my $id = $hist_canvas->get_unique_id($canvas);
                        
                        my $hist_chooser = $self->hist_chooser;
                        my @choosermap = $hist_chooser->chooser_map;

                        # get comment from choosermap (choosermap is a 2 dimensional array)
                        $comment_string = $choosermap[$id]->[$self->comment_index] ; 
                                                
                        $comment_entry->focusForce;
                        });

        $self->toplevel($top);
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
    
    sub update_db_comment{
        
        my $self = shift @_ ;
        my $new_string = shift @_;      # new string to be updated
        
        
        my $hist_chooser = $self->hist_chooser;
        my @choosermap = $hist_chooser->chooser_map;
        my $canvas = $self->history_canvas;
        
       
        my ($time_variable, $seq_id_variable , $ctg_id, $current_time);

        my $row_selected = $canvas->get_selected_row_id($canvas);
        
        
        if ( $row_selected > -1 ) #checks that something has been selected.
        {
            
            $time_variable   =  $choosermap[$row_selected]->[$self->time_index];
            $ctg_id          =  $choosermap[$row_selected]->[$self->ctg_id_index];

            $choosermap[$row_selected]->[$self->comment_index] = $new_string ;
       
#            warn "time $time_variable , ctg $ctg_id , comment$choosermap[$row_selected]->[4] ";
            $hist_chooser->chooser_map(@choosermap);
           
            # assuming that a combination of time and contig_name will be unique.  
            my $sth = prepare_statement(qq{
                    UPDATE sequence_note 
                    SET note = ?
                    WHERE contig_id = ?
                    AND note_time =  ?
                                    });
                                  
             $sth->execute($new_string, $ctg_id, $time_variable);
            
        }
        else
        {   warn "nothing has been selected to update";

        }
    }

    ##sub update_window{
    ##    warn "dont forget to update this subroutine" ;
    ##    my ($self) = @_;
    ##    
    ##}
  
    
    sub display{
        my $self = shift @_;
        my $top = $self->toplevel;
         
        $top->deiconify;
        $top->raise;        
    }


}

1    
    
__END__

=head1 NAME - ana_notes

=head1 SYNOPSIS

my $history_popup = HistoryPopup->new(1,3,5);
$history_popup->make_popup($canvas , $contig_db_id);


the elements of the array are (currently) optional. They are the array index of the contig_id, the time and the note in the choosermap.



