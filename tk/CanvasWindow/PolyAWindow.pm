## PolyAWindow.pm

package CanvasWindow::PolyAWindow ;

use strict ;
use Carp;
use Tk ;
  
use base 'CanvasWindow';

sub toplevel {
    my( $self ) = @_;
    
    return $self->canvas->toplevel;
}

sub xace_seq_chooser{
    my ($self , $seq_chooser) = @_ ;
    if ($seq_chooser){

        $self->{'_xace_seq_chooser'} = $seq_chooser;
    }
    return $self->{'_xace_seq_chooser'} ;
}

sub slice_name {
    my ($self , $name) = @_ ;
    if ($name){
        $self->{'_slice_name'} = $name ;
    }
    return $self->{'_slice_name'};
}

sub add_CloneSequence{
    my ($self , $cs ) = @_;
    push(@{$self->{'_cs_list'}},$cs);   
}

sub get_all_CloneSequences{
    my $self = shift;
    my $xaceSeqChooser = $self->xace_seq_chooser();
    my $slice_name     = $self->slice_name();
    return ($xaceSeqChooser->get_CloneSeq($slice_name));
#    return $self->{'_cs_list'} ? @{$self->{'_cs_list'}} : (); 
}

##-----------------------------------------
# these arrays store the original values of 
# the polyA sites / signals from the clone_seq
# ie before they have been edited
sub stored_array_refs{
    my ($self, $type, $array_ref) = @_;
    return [] unless $type;
    if (ref($array_ref) eq 'ARRAY'){
	$self->{'_stored_arrays'}->{$type} = $array_ref;
    }
    return $self->{'_stored_arrays'}->{$type};
}
#-----------------------------------
# entry box variable refs are stored (and retrieved from these routines)
sub entry_pairs{
    my ($self, $type, $entry_pair) = @_;
    return () unless $type;
    if (ref($entry_pair) eq 'ARRAY'){
	push(@{$self->{'_entry_pairs'}->{$type}}, $entry_pair);
    }
    return @{$self->{'_entry_pairs'}->{$type}};
}

##-----------------------------------------
## store the frames used for each of the arrays of entry widgets
sub sub_frame{
    my ($self, $type, $frame) = @_;
    return unless $type;
    if($frame){
	$frame->bind('<Destroy>', sub{ $self = undef; } );
	$self->{'_sub_frame'}->{$type} = $frame;
    }
    return $self->{'_sub_frame'}->{$type};
}

#------------------------------------------

#takes the clone_sequence(s) and generates the internal arrays based on them 
sub initialize{ 
    my ($self ) = @_ ; 
    
    ## create arrays based on the clone_sequences
    my @polyA_list;
    if (my @cs_list = $self->get_all_CloneSequences){
        foreach my $clone (@cs_list){
            push (@polyA_list , $clone->get_all_PolyAs());
        }
        
        my @site_array;
        my @signal_array;
        foreach my $polyA (@polyA_list){
            my $start = $$polyA[1] ;
            my $end = $$polyA[2] ;
            if ($polyA->[0] =~ /site/ ){
                #note we are using references here - as that is what is supplied to the entry widgets
                #2 coords for each poly a site
                push (@site_array , [ \$start , \$end ]);

            }
            elsif($polyA->[0] =~ /signal/ ){
                # 2 coords for each poly a signal;
                push (@signal_array , [ \$start , \$end ]);
            }
            else{
                print STDERR "Poly A from CloneSequence not in expected format.\nExpected PolyA_signal or PolyA_site , got ".$polyA->[0] ;
            }
        }
        
        #if we dont have any coords for the array - create empty references
        if (scalar(@site_array) == 0 ){
            my $start = '' ;
            my $end = '';
            my @site_array = ([\$start, \$end]) ;
        }
        if (scalar(@signal_array) == 0 ){
            my $start = '';
            my $end = '' ;
            my @signal_array = ( [ \$start, \$end ]) ;
        }        
        $self->stored_array_refs('site', \@site_array);
        $self->stored_array_refs('signal', \@signal_array);
    }      
}


## draw subroutine will create a set of frames for each part of the GUI
## $label_frame hold the labels at the top
## $button frame holds the buttons at the bottom
## the array frame sits in the middle and hold two further frames, containing a variable number of entry widgets
## clicking the buttons allows the annotators to add extra entry widgets to either of these two frames
sub draw{
    my ($self) = @_ ; 
    
    my $tl = $self->toplevel;
    my $slice_name = $self->slice_name ||
        confess 'the polyA window needs to be given a slice name' ;    
    $tl->title("Poly A sites / signals for : $slice_name");
    
    
    # hope xace_seq_chooser exists
    my $write_acces = $self->xace_seq_chooser->write_access();
    
    my $hide_window = sub { $self->hide_window  };

    #my $close_window = sub { $self->close_window, $self = undef };
    $tl->bind('<Control-w>',          $hide_window);
    $tl->bind('<Control-W>',          $hide_window);
    $tl->protocol('WM_DELETE_WINDOW', $hide_window);

    ## this will redraw the subframes portion of the window - so that it displays the stored coords after it has been closed and refreshed
    my $redraw = sub {$self->draw_subframes};
    $tl->bind('<<redraw_polya>>' , $redraw) ; 

  
    my $canvas = $self->canvas();
    $canvas->configure(-background => 'light grey');
    
    my $top_frame = $tl->Frame()->pack(
        -side   => 'top',
        -fill   => 'x',
        -padx   => 35,
        -before => $canvas,
        );
    my $Button_frame = $tl->Frame(-relief => 'groove' )->pack(-side => 'top' ,-fill=>'both') ;
        
    my $sig_label = $top_frame->Label(-text => 'PolyA Signal')->pack(-side => 'left', -padx => 5) ;
    my $site_label = $top_frame->Label(-text => 'PolyA Site' )->pack(-side =>'right', -padx => 5);
    
    my $add_signal = $write_acces ? sub { $self->add_entry_widget('signal') } : sub { return 1 };
    $top_frame->Button( -text => 'Add Signal',
                        -underline => 6,
                        -relief => 'groove',
			-state  => $write_acces ? 'normal': 'disabled',
                        -borderwidth => 2 ,
                        -command => $add_signal)->pack( -side => 'left' , -after=>$sig_label );
    $tl->bind('<Control-G>', $add_signal) ;
    $tl->bind('<Control-g>', $add_signal) ;
    
    my $add_site = $write_acces ? sub { $self->add_entry_widget('site') } : sub { return 1 };
    $top_frame->Button( -text => 'Add Site',
                        -underline => 6,
                        -relief => 'groove',
			-state  => $write_acces ? 'normal': 'disabled',
                        -borderwidth => 2 ,
                        -command =>  $add_site )->pack( -side => 'right' , -before => $site_label );
    $tl->bind('<Control-T>' , $add_site ) ;
    $tl->bind('<Control-t>' , $add_site ) ;
    
    ##add save / close button at bottom
    $Button_frame->Button(-text => 'Save co-ordinates' ,
                          -underline => 0 ,
                          -relief => 'groove',
                          -borderwidth => 2 ,  
                          -command => sub {$self->save_details }  )->pack( -side => 'left' , -padx=> 45);
    $tl->bind('<Control-S>' , sub {$self->save_details} ) ;
    $tl->bind('<Control-s>' , sub {$self->save_details} ) ;
    
    
    $Button_frame->Button(-text => 'Close' ,
                          -relief => 'groove',
                          -borderwidth => 2 ,  
                          -command => $hide_window  )->pack( -side => 'right' , -padx=>45 );
    $tl->bind('<Control-x>' , $hide_window ) ;
    $tl->bind('<Control-X>' , $hide_window ) ;
    
    $tl->bind('<Destroy>', sub{
        $self = undef;
        });
    
    $self->draw_subframes;
}


# this may be called when the window has been withdrawn then raised - 
# so that it displays the actual stored coords, rather than messed up values (is close and dont save)
sub draw_subframes{
    my ($self) = @_ ;
    # get the arrays (or produce arrays with blank entries)
    ##my ($empty_1 , $empty_2 , $empty_3 , $empty_4) = ('' , '' , '', '' );
    ##my ($empty_1 , $empty_2 , $empty_3 , $empty_4) = ('') x 4;
    my $canvas = $self->canvas;
    my @site  = @{$self->stored_array_refs('site')};
    my @signal = @{$self->stored_array_refs('signal')};
    
    if (scalar(@site )< 1){@site = $self->create_empty_array} ; 
    if (scalar( @signal) < 1){@signal = $self->create_empty_array} ; 
    
  #  my @largest  = (scalar(@signal) > scalar(@site)) ? @signal: @site ;

    $self->{'_entry_pairs'} = undef ;

    # remove existing subframes
    if( my $sigframe =  $self->sub_frame('signal')) {
        $canvas->delete($sigframe->id , 'signal_frame'); 
    }
    if( my $siteframe =  $self->sub_frame('site')) {
        $canvas->delete($siteframe->id  , 'site_frame' );
    }

    my $signal_frame = $canvas->Frame() ;
    my $site_frame = $canvas->Frame();
   
    
    $self->sub_frame('signal', $signal_frame);
    $self->sub_frame('site',   $site_frame);
    
    $self->populate_subframe('signal', @signal);
    $self->populate_subframe('site', @site) ;
   
    $canvas->createWindow( 0, 0 , -window=> $signal_frame , -anchor=> 'nw',  -tags=>'signal_frame');
    $canvas->update;
    
    $canvas->createWindow( $signal_frame->width + 15  , 0 , -window=> $site_frame , anchor => 'nw' , -tags=>'site_frame');
    $canvas->update();
    
    $self->fix_window_min_max_sizes;    
}



sub create_empty_array{
    my $self = @_ ;
    
    my $start = '' ;
    my $end = '' ;
    my @array = ([\$start , \$end  ]);
    
    return @array;
}


## adds a set of Entry widgets and corresponding  radionbuttons to the frame for each variable in @array
sub populate_subframe{
    my ($self , $frame_type , @array) = @_ ;

    my $frame = $self->sub_frame($frame_type); 

    foreach my $entry_pair (@array){
        my $entry_frame = $frame->Frame->pack(-side => 'top',
					      -fill => 'none'
					      );
        my $coord_1 = ${$entry_pair->[0]};
        my $coord_2 = ${$entry_pair->[1]};
        my $coord_1_ref = \$coord_1;
        my $coord_2_ref = \$coord_2;                           

        my $strand;
        my $update_cmd = sub { update_entry($coord_1_ref , $coord_2_ref , \$strand , $frame_type ); };
        

            


        my $start_entry = $entry_frame->Entry(
					      -textvariable => $coord_1_ref ,
					      -width => 10 ,
					      -relief => 'sunken' )->pack(-side => 'left' );

        my $end_entry = $entry_frame->Entry(
                                            -textvariable => $coord_2_ref ,
					    -width => 10 ,
					    -relief => 'sunken' )->pack(-side => 'left' ); 



       
	$start_entry->bind('<Return>',  sub {
	    update_entry($coord_1_ref , $coord_2_ref , \$strand , $frame_type, 'start' )
	    });
	$end_entry->bind('<Return>',  sub {
	    update_entry($coord_1_ref , $coord_2_ref , \$strand , $frame_type, 'end' )
	    });

        $entry_frame->bind('<Destroy>', sub{ $self = undef; } );




            
	my $pos_button = $entry_frame->Radiobutton(
						   -command => $update_cmd, 
						   -text => '+' ,
						   -variable => \$strand ,
						   -value => '+',
						   -borderwidth => 2 ,
						   -relief => 'groove')->pack(-side=> 'left') ;
	my $neg_button = $entry_frame->Radiobutton(
						   -command => $update_cmd,
						   -text => '-' ,
						   -variable => \$strand , 
						   -value =>'-',
						   -borderwidth => 2 ,
						   -relief => 'groove')->pack(-side=> 'left' ) ;
      






	my $delete = sub{ ${$coord_1_ref} = '' ; ${$coord_2_ref} = '' ;  } ; 
	my $clear_buttton = $entry_frame->Button(
						 -text => 'Delete',
						 -relief=> 'flat' ,
						 -command => $delete ,
						 -borderwidth => 1,
						 )->pack(-side =>'left');
        
        ## add entry to an array , so values can be retrieved later
        $self->entry_pairs($frame_type, [ $coord_1_ref , $coord_2_ref ]);


        ## automatically select the button based on the given coords - gives the positive strand as the default 
        # 0's in brackets, so we dont get warnings when $coord's are non numeric 
        if (($coord_1 || 0) > ($coord_2 || 0)){
            $neg_button->select;
	} else {
            $pos_button->select;
        }
        $start_entry->focus();
    }  
}



## brings up another site / signal entry box  to associate with the locus (when a new poly A signal / site is to be added)
sub add_entry_widget{
    my  ($self, $type) = @_;
    
    my $start = '' ;
    my $end = '' ;
    #add element to array then redraw canvas
    my $entry_pair = [\$start , \$end ];
    $self->populate_subframe($type , $entry_pair);
    $self->fix_window_min_max_sizes;
    
}


## when a + or - radio button is pressed, this will automatically update the corresponding entry, based on strand
{
    sub update_entry {
	# my ($self , $start , $end , $strand_ref , $type, $entry) = @_;
	my ($start , $end , $strand_ref , $type, $entry) = @_;
	# Remebmer that $start AND $end are REFERENCES - not values (lots of $$ in this subroutine)
	
	my $length;
	if ($type eq 'signal'){
	    $length  = 5;  
	}else{
	    $length  = 1 ;
	}
	
	## adds length to a +ve strand and subtracts from a -ve strand
	my $multiplier;
	if ($$strand_ref eq '-'){
	    $multiplier = -1 ;
	}else{
	    $multiplier = 1 ;
	}
	
	if ($entry) {
	    if ($entry eq 'start') {
		$$end = '';
	    }
	    elsif ($entry eq 'end') {
		$$start = '';
	    }
	}
	
	## we have both coords - check strand orientation is correct. Otherwise we have one coord and can calculate other
	if (($$start =~ /\d/) && ($$end =~ /\d/)) {
	    if ( (($$start > $$end) && ($$strand_ref eq '+')) || (($$start < $$end) && ($$strand_ref eq '-')) ) {
		($$start , $$end ) = ( $$end , $$start ) ;
	    }   
	}
	elsif ( $$start =~ /\d/) { 
	    $$end = $$start + ($length * $multiplier) ; 
	}elsif( $$end =~ /\d/){
	    $$start = $$end - ($length * $multiplier) ; 
	}else{
	    print STDERR "nothing to update\n";
	}
    }

}
#brings up a dialogue which asks user if he/she wants to save coords (only when unsaved)
sub dialogue_for_save{
    my ($self) = @_ ;

    # hope xace_seq_chooser exists
    return 1 unless my $write_acces = $self->xace_seq_chooser->write_access();
    # checks to see if any (ie an ace file is created) and it is not invalid
    my ($status , $ace) = $self->create_ace_file;
    if ($ace){
        my $save_changes = $self->toplevel->messageBox(
            -title      => "Save PolyA's for " , 
            -message    => "Do you wish to save the changes for '" . $self->slice_name . "'?", 
            -type       => 'YesNoCancel',
            -icon       => 'question',
            -default    => 'Yes',
            );

        if ($save_changes eq "Yes"){
            my $result = $self->save_details($status ,$ace );
            return 0 if $result eq 'Cancel';
        }elsif($save_changes eq 'Cancel'){
	    return 0;
	}
    }
    return 1;
}
sub close_window{
    my ($self) = @_;
    # return 0 if user decides to cancel [see save_window]
    $self->dialogue_for_save() or return 0;
    # cleaning out this object's xace
    $self->clean_XaceSeqChooser();
    # incase xace has managed to close itself. this was in previous version
    $self->toplevel->destroy;
    # making self undef, probably removes need for clean_XaceSeqChooser
    $self = undef;
    return 1; # sucess for closing
}

sub hide_window{
    my ($self) = @_;
    # return 0 if user decides to cancel [see save_window]
    $self->dialogue_for_save() or return 0;
    $self->xace_seq_chooser->withdraw_PolyAWindow($self);
}

sub clean_XaceSeqChooser{
    my $self = shift;
    $self->{'_xace_seq_chooser'} = undef;
}

sub save_details{
    my ($self ,  $status , $ace ) =  @_ ;  
    
    # create .ace file based on new / updated coords if none passed 
    unless ($ace){
        ($status, $ace) = $self->create_ace_file ;
    }

    if ($ace){
        ## use xace_remote to parse this file 
        my $xace_seq_chooser = $self->xace_seq_chooser ;
        my $xace_remote = $xace_seq_chooser->xace_remote ;
        if ($xace_remote){
            my $result = 'Yes' ;
            if ($status  eq 'errors'){
                ### This is too complicated - we should do something simpler
                $result = $self->toplevel->messageBox(    -title => 'Sequence '. $self->slice_name , 
                                            -message => "Some coordinates were invalid.\nSave the Valid coords?", 
                                            -type => 'YesNoCancel', -default => 'Yes');
            }
            if ($result ne 'Yes'){
                print STDERR 'not saving';
                return $result;
            }
            print STDERR $ace; 
            $xace_remote->load_ace($ace);
            $xace_remote->save;
            $xace_remote->send_command('gif ; seqrecalc');
            print STDERR "saved polyA's to xace"; 
            
            if ($status ne 'errors' ){
                $self->_update_arrays();
                return 'saved';
            }
            return 'part saved'
        }
        else{       
            my $result = $self->toplevel->messageBox(    -title => 'Error!', 
                                            -message => "No Xace attached,\nCan't save Poly A details.", 
                                            -type => 'OKCancel', -default => 'Ok');
            return $result;
        } 
    }
    else{
        return 'nothing to save';
    }
}


## compares the original array given to the GUI, to the coords currently in the entry widgets
## and creates a .ace file deleting any changed  coords, and adding the new versions, as well as new sets of coords
sub create_ace_file{
    my ($self ) =   @_  ;

    my $slice_name = $self->slice_name ;        
    my $ace = '' ;
    my $status = 'good' ;    
    foreach my $type ( 'signal' , 'site' ){
        #compare the original array coords with the current coords in the widgets 
        my @original_array =  @{$self->stored_array_refs($type)} ;    
        
        my @new_array = $self->entry_pairs($type);
    
        foreach my $old_coord_pair (@original_array) {
            my $old_start_ref = $old_coord_pair->[0] ;
            my $old_end_ref = $old_coord_pair->[1] ;
            unless (@new_array ) {@new_array = $self->create_empty_array} ; # should get used when new array is bigger than old one
            my $new_coord_pair = shift @new_array ;
             
            my $new_start_ref = $new_coord_pair->[0];
            my $new_end_ref = $new_coord_pair->[1];
            
            unless (($$old_start_ref == $$new_start_ref) && ($$old_end_ref == $$new_end_ref) ) {
                ## original coord changed
                ## write a deletion then an addition line
                
                unless (($$old_start_ref eq '') && ($$old_end_ref eq '')){
                    $ace .= qq{Sequence "$slice_name"\n};
                    $ace .= qq{-D Feature "polyA_$type" $$old_start_ref $$old_end_ref  0.5 "polyA_$type"\n\n} ;
                }
                ($status ,$ace) = $self->write_ace_line($status , $ace , $$new_start_ref , $$new_end_ref , $type);           
                
            }
        }
        foreach my $new_entries (@new_array ){
            my $start_ref = $new_entries->[0] ;
            my $end_ref = $new_entries->[1]  ;

            ($status ,$ace) = $self->write_ace_line($status , $ace , $$start_ref , $$end_ref , $type);
        }    
    }
    unless ($ace  eq ''){
        #print STDERR  "created ace file...\n" .$ace;
        return  ($status , $ace) ;    
    }
    else{
        return ($status); 
    }    
}

# writes a line to the ace file if the coords are valid, otherwise returns status with errors
sub write_ace_line{
    my ($self , $status , $ace , $start , $end , $type) = @_ ;
    
    my $slice_name = $self->slice_name ;
    
    ($start, $end) = $self->validate_coords($start , $end , $type) ;
    if (($start =~ /(\d)+/) && ($end =~ /(\d)+/)) { 
        $ace .= qq{Sequence "$slice_name"\n};
        $ace .= qq{Feature "polyA_$type" $start $end 0.5 "polyA_$type"\n\n} ;
    }
    else{
        if ($start eq 'invalid'){
            $status = 'errors' ;
        }
    } 
    return ($status , $ace)
}

# checks that the coordinates are the expected distance apart 
# returns -1, -1 if whitespace characters are present in both elements - ie take it as a deleted pair of coords
sub validate_coords{
    my ($self , $start , $end , $type) = @_ ;
    
    my $diff ;
    if ($type eq 'site'){
        $diff = 1 ;
    }
    else{
        $diff = 5 ;
    }

    ## need to change this to assure that both coord are numeric
    if (($start =~ /(\d)+/) && ($end =~ /(\d)+/)){
        if (($start - $end  == $diff) || ($end - $start == $diff)){
            return ($start , $end) ;
        }    
        else {
            print STDERR "$type coordinates '$start' and '$end' are not the expected distance apart\n" ;     
            return ('invalid', 'invalid')  ; 
        }
    }
    else{
        if ( ($start eq '')   && ($end eq '') ){
            return ('blank','blank');
        }
        else{
            print STDERR "Coordinates $start and $end are invalid.";
            return ('invalid', 'invalid');                
        }
    }
    
}



#when coords are saved , swap current array for stored ones - so that user isnt asked if they want to save on closing
## need to make a copy of the elements in the array as copying the array just gives us references to the same values
sub _update_arrays{
    my ($self) = @_ ;
    
    my @site_entries = $self->entry_pairs('site');
    my @signal_entries = $self->entry_pairs('signal');
    
    foreach my $type ( qw(signal site) ) {
        my @old_array = $self->entry_pairs($type);
        
        my @new_array;
        
        foreach my $ref_pair (@old_array){
            my $start = ${$$ref_pair[0]};
            my $end = ${$$ref_pair[1]};
            
            if ( $start =~ /\d+/ && $end =~ /\d+/){
                push (@new_array , [ \$start, \$end] ) ; 
            }
        }
        
        $self->stored_array_refs($type, \@new_array);
    }
}

sub DESTROY {
    my ($self) = @_;
    warn "Destroying PolyAWindow for ".$self->slice_name."\n";
}

1;



__END__

=head1 NAME - CanvasWindow::PolyAWindow

=head1 AUTHOR

Colin Kingswood <email> ck2@sanger.ac.uk


