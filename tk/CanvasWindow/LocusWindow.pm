

package CanvasWindow::LocusWindow;

use strict;
use Tk;
use base 'CanvasWindow';
use Data::Dumper;

sub new{
    my ($pkg , $toplevel ,$locus ) = @_ ;
    my $self = bless {}, $pkg ;

    $self->toplevel($toplevel);    
    
    if ($locus) {
        $self->locus($locus);
    }
    return $self ;
}

sub locus{
    my ($self) = @_ ; 
      
    my $ec = $self->last_exon_canvas;
    return $ec->SubSeq->Locus;
}

sub toplevel{
    my ($self , $tl) = @_ ;
    if ($tl){
        $self->{'_toplevel'} = $tl ;
    }
    return $self->{'_toplevel'};
}

sub set_window_title{
    my ( $self , $title ) = @_ ;
    $self->toplevel->title($title);
}

sub last_exon_canvas{
    my ($self , $canv) =@_ ;
    if ($canv){
        $self->{'_exon_canvas'} = $canv ;
    }
    return $self->{'_exon_canvas'} ;
}


sub xace_seq_chooser{
    my ($self) = @_  ;
    return $self->last_exon_canvas->xace_seq_chooser ;
}


sub initialize{
    my ($self) = @_ ;
    
    my $top = $self->toplevel;
    $self->{'_locus_window'} = $top;
    $top->protocol('WM_DELETE_WINDOW', sub{ $top->withdraw });
    
    my $label_frame = $top->Frame;
    $label_frame->pack(-side => 'top');
    
    my $locus_name ;
    eval{ $locus_name = $self->Locus->name };
    $locus_name ||= '';
    $self->locus_name_ref(\$locus_name);
    
 

    my $active_frame = $top->Frame()->pack(-side => 'top');

    my $update_checkbutton = sub {$self->update_checkbutton} ;
    my $combo_box = $active_frame->ComboBox( -listheight => 10,
                                    -label      => 'Locus: ',
                                    -width      => 18,
                                    -variable   => \$locus_name,
                                    #-text       => $locus_name,
                                    -exportselection    => 1,
                                    -background         => 'white',
                                    -selectbackground   => 'gold',
#                                    -font               => [$self->font, $self->font_size, 'normal'],
                                    -command            => $update_checkbutton ,
                                    )->pack(-side => 'left');

    $combo_box->bind('Return' , sub{$self->run_command});
    $self->_combo_box($combo_box);
    
    my $checkbox_var = 0 ;
    $self->_is_known_ref(\$checkbox_var);
    my $checkbox = $active_frame->Checkbutton(  -text    => 'is known?',
                                                -variable => \$checkbox_var ,
                                                )->pack(-side =>'left') ;
                                                
    my $button = $active_frame->Button( -text => 'Save', 
                                        -command => sub {$self->run_command } ,
                                        )->pack(-side => 'left');
}

sub _is_known_ref {
    my ($self , $var_ref) = @_;
    if ($var_ref){
        $self->{'_checkbox_ref'} = $var_ref ;   
    }
    return $self->{'_checkbox_ref'};
}

sub _combo_box{
    my ($self, $combo) =@_ ;
    if ($combo){
        $self->{'_combo'} = $combo ;
    } 
    return    $self->{'_combo'};
}
sub _button {
    my ($self , $button) = @_ ;
    if ($button ){
        $self->{'_button'} = $button ;    
    }
    return $self->{'_button'};
}

sub locus_name_ref{
    my ($self , $name_ref ) = @_ ;
    if ($name_ref){
        $self->{'_locus_name_reference'} = $name_ref;
    }
    return  $self->{'_locus_name_reference'} ;    
}


#this is the type of operation currently being peformed on the Locus object (rename / merge / new ) 
sub state{
    my ($self , $state) = @_ ;
    if ($state ){
        $self->{'_state'} = $state ;
    }
    return $self->{'_state'};    
}


sub update_checkbutton{
    my ($self) = @_ ;
    my $xace = $self->xace_seq_chooser;
    my $locus_name = ${$self->locus_name_ref} || return;
    my $locus = $xace->get_Locus( $locus_name);
    
    my $checkbox_ref = $self->_is_known_ref;
    my $gene_type ;
    eval { $gene_type = $locus->gene_type } ;
    if ($@){
        ## if there are errors, the gene type has not been set  
        $$checkbox_ref = 0 ;    
    }else{
        $$checkbox_ref = 1 ;
    }
}

sub show{
    my ($self, $state) = @_ ;
    
#    warn "state from here $state";
    my $top = $self->toplevel();
    $top->resizable(1, 1);
    my $combo = $self->_combo_box ; 
    
    if ($state eq 'new'){
        $self->set_window_title('New Locus for SubSeq ' . $self->last_exon_canvas->SubSeq->name);
    }
    elsif($state eq 'edit'){
        $self->set_window_title('Edit Locus ' . $self->locus->name);
    }
    
    $self->update_checkbutton ;
    
    $self->state($state);
    if ($state eq 'new'){
        $combo->configure(-listcmd => 
            sub{
                my @names = ('');
                $combo->configure(
                -choices   => [@names],
                #-listwidth => scalar @names,
                );       
            });
        ${$self->locus_name_ref} = '';
    }
    elsif($state eq 'edit'){ # state eq merge / swap ...
        $combo->configure(-listcmd => 
            sub{
                my @names = $self->xace_seq_chooser->list_Locus_names;
                $combo->configure(
                -choices   => [@names],
                );       
            });
         ${$self->locus_name_ref} = $self->locus->name; 
    }

    ##position window
    ##my $geometry = $self->toplevel()->geometry() ;
    ##warn "geometry $geometry " ;
    ##my ($size, $xpos , $ypos) = $geometry =~ /(\d+x\d+)?[+-]?(\d+)?[+-]?(\d+)?/ ;
    ##warn "x= $xpos y = $ypos ";
    ##$self->toplevel()->geometry( "+50+50") ; 
    
    

    $combo->focus ;
    $self->toplevel->deiconify ;
    $self->toplevel->raise ;
    $top->resizable(0 , 0);
}

### this is called when the save button is pressed. Transfers control to the appropriate method (new / edit) based on the state variable
sub run_command{
    my ($self) = @_ ;
    my $state = $self->state();
    
    my $method = $state. '_locus' ;
    $self->$method;
}

sub edit_locus{
    my ($self) = @_ ;
    
    my @list = $self->xace_seq_chooser->list_Locus_names() ;
    my $current_entry = ${ $self->locus_name_ref } ;
    if ($current_entry =~ /\S/ ){
        my $current_name  = $self->locus->name ;
        if (grep {$current_entry eq $_ } @list) {
            if ($current_entry eq $current_name ){
                # we have the same name we started with - assume 'is_known' value changed            
                $self->state('change_type') ;
                $self->change_gene_type;
                return ;
            }         
            my $answer = $self->toplevel->Dialog(-title => 'Please Reply', 
                -text => "Merge locus with another or replace?\n(a merge will keep the name $current_name and remove $current_entry)", 
                -default_button => 'replace', -buttons => ['merge','replace','cancel'], 
                -bitmap => 'question' )->Show(  );
            if ($answer eq 'merge') {
            # ... do something ...
#                warn "merge";
                $self->state('merge');
                $self->merge_locus;
            }
            if ($answer eq 'replace'){
#                warn "replace";
                $self->state('swap');
                $self->swap_locus ;
            }
            if ($answer eq 'cancel'){
                return ;
            }
        }
        else{
            my $answer = $self->toplevel->messageBox(
                -title => 'Please Reply', 
                -message => 'Rename locus?', 
                -type => 'YesNoCancel', -icon => 'question', -default => 'yes');

            if ($answer eq 'Yes'){
                $self->rename_locus;   
            }
        }
    }
    else{
        $self->toplevel->messageBox(
            -title => 'Error', 
            -message => 'You need to enter a value in the Combo', 
            -type => 'Ok');
    }
}
    


sub swap_locus{
    my ($self) = @_ ;
    my $new_locus_name = ${ $self->locus_name_ref } ; 
    my $ec = $self->last_exon_canvas;
    my $new_locus = $self->xace_seq_chooser->get_Locus($new_locus_name);
    # update exon canvas display.....
    $ec->update_locus($new_locus); 
    # update ace display
    my $ace = $ec->SubSeq->ace_string;  
    $self->xace_seq_chooser->update_ace_display($ace);
    $self->toplevel->withdraw ;  
}

## should not be needed any more - achieved with a 'new' folowed by a 'rename';
##sub split_locus{
##    my ($self) = @_ ;
##    
##    ## clone original locus & store that as $self->locus , update in the xace_seq_chooser objects as well
##    my $new = $self->locus->clone;
##    $self->locus($new) ;
##    $self->store_new_locus($new) ; 
##    $self->toplevel->withdraw ;
##}

sub new_locus{
    my ($self) = @_ ;
    my $new = Hum::Ace::Locus->new;
    $self->store_new_locus($new) ; 
    $self->toplevel->withdraw ;
}

sub set_gene_type{
    my ($self , $locus ) = @_ ;
    
    my $is_known = ${$self->_is_known_ref};
    if ($is_known) {
#        warn "should be setting the gene type to known ";
        $locus->gene_type('Known');
    }else{
        warn 'unsetting the gene type!!!!!!!' ;
#        # ok, not the 'proper' way to have to do things .....
        $locus->unset_gene_type()  ;
    }
}


sub change_gene_type{
    my ($self ) = @_ ;
    my $locus = $self->locus ;

    $self->set_gene_type($locus) ;
    my $ace = $locus->is_known_string ;
    my $xace = $self->xace_seq_chooser ;
    $xace->update_ace_display($ace);
    $self->toplevel->withdraw ;
}


sub store_new_locus{
    my ($self , $locus) = @_ ;

    my $new_name = ${$self->locus_name_ref};
    unless ($new_name){
        $self->toplevel->messageBox(-title => 'Error', 
                                    -message => 'You need to supply a new name for the new locus', 
                                    -type => 'Ok');
        return ;
    }
    $locus->name($new_name);
    
       
    $self->set_gene_type($locus) ;

    my $xace = $self->xace_seq_chooser() ; 
    $xace->add_new_Locus($locus);
    
  
    unless( $self->last_exon_canvas()->update_locus($locus)) {
        return ; # basically if the locus name has been assigned;
    } 
    
    my $ace = $self->last_exon_canvas->SubSeq->ace_string(); 
    $ace .= $self->locus->is_known_string ;

    $xace->update_ace_display($ace);
    $self->toplevel->withdraw ;
}

sub rename_locus{
    my ($self) = @_ ;
    
    $self->update_canvases();
   
    my $new_name  = ${ $self->locus_name_ref };
    my $locus = $self->locus ; 
    
    my $old_name = $locus->name ;

    $old_name ||= '' ;  
    $locus->name($new_name) ;
    
    $self->set_gene_type($locus) ;
    #fine till here -> need to update all exon canvases and acedb display!!!!
    my $xace = $self->xace_seq_chooser();
    $xace->rename_loci($old_name , $new_name ) ;
    
    $self->toplevel->withdraw ;
}

sub merge_locus{
    my ($self ) = @_ ;
    ## get newly selected locus (as well as current one)
    ## merge the two loci together 
    ## go through ALL exon canvases that are open , and swap locus if it is relevant
    ## send update to acedb; 
    ## swap all SubSeqs as well;

    my $xace = $self->xace_seq_chooser();
    my $current_locus = $self->locus;
    my $current_locus_name = $current_locus->name ;

    $self->update_canvases ;    
    # this updates the locus object in each of the the subseq objects 
    my $selected_name = ${ $self->locus_name_ref } ;
    $self->set_gene_type($current_locus);
    $xace->merge_loci($current_locus_name , $selected_name ) ;
    $self->toplevel->withdraw ;
}

sub update_canvases{
    my ($self) = @_ ;
    
    my $xace = $self->xace_seq_chooser();   
    foreach my $name ($xace->list_all_subseq_edit_window_names) {
        my $top = $xace->get_subseq_edit_window($name) or next;
        $top->deiconify;
        $top->raise;
        $top->update;
        $top->focus;
        $self->is_current(1);
        $top->eventGenerate('<<update_locus>>');
        $self->is_current(0);
    } 
}

sub is_current{
    my ($self , $value ) = @_ ;
    
    if (defined $value){
        $self->{'is_current'} = $value ;
    }
    return $self->{'is_current'} ;
}

sub get_locus_old_name{
    my ($self , $string) = @_ ;
    
    print $string if $string ;
    my $state = $self->state; 
    my $selection ;
    
    if ($state eq 'rename'){
        $selection = $self->locus->name ;
        #warn "old name from Subseq " . $selection ;
    }
    elsif ($state eq 'merge'){
        my $selection_ref = $self->locus_name_ref;
        $selection = $$selection_ref;
        #warn "old name from combo " . $selection
    }
    return $selection ;
}

sub get_locus_new_name{
    my ($self) = @_ ;
    my $selection ;
    if ($self->state eq 'merge') {
        $selection =  $self->locus->name;

    }
    elsif($self->state eq 'rename'){
        my $selection_ref = $self->locus_name_ref;
        $selection = $$selection_ref;    

    }
    return $selection;
}


sub DESTROY{
    my ($self) = @_ ;
    $self->xace_seq_chooser->remove_locus_window($self->locus);
    $self->{'_exon_canvas'} = undef ; 
}


1;
