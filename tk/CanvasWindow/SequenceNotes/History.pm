
### CanvasWindow::SequenceNotes::History

package CanvasWindow::SequenceNotes::History;

use strict;
use Carp;
use Data::Dumper;
use base 'CanvasWindow::SequenceNotes';

sub clone_index{
    my ($self, $index) = @_;
    if (defined($index)){
	$self->{'_clone_index'} = $index;
	if($self->SequenceSet){
	    my $cs_list = $self->get_CloneSequence_list();
	    my $prev_button = $self->prev_button();
	    my $next_button = $self->next_button();
	    return $index unless $prev_button;
	    if($index && $index + 1 >= scalar(@$cs_list)){
		$next_button->configure(-state => 'disabled');
		$prev_button->configure(-state => 'normal');
	    }elsif(!$index){
		$next_button->configure(-state => 'normal');
		$prev_button->configure(-state => 'disabled');
	    }else{
		$next_button->configure(-state => 'normal');
		$prev_button->configure(-state => 'normal');
	    }
	}
    }
    return $self->{'_clone_index'};
}

sub next_button{
    my ($self, $next) = @_;
    if ($next){
	$self->{'_next_button'} = $next;
    }
    return $self->{'_next_button'};
}
sub prev_button{
    my ($self, $prev) = @_;
    if ($prev){
	$self->{'_prev_button'} = $prev;
    }
    return $self->{'_prev_button'};
}

sub entry_text_ref{
    my ($self , $entry_ref) = @_ ;
    if ($entry_ref){
        $self->{'_entry_ref'}  = $entry_ref;
    }
    return  $self->{'_entry_ref'} ;
}


sub current_clone{
    my ($self , $clone) = @_;
    my $cs_list = $self->get_CloneSequence_list();
    my $cloneSeq = @$cs_list[$self->clone_index];

    my $title = "History for " .$cloneSeq->contig_name . "  " .$cloneSeq->clone_name;
    $self->canvas->toplevel->title($title);
    return $cloneSeq;
}

sub initialise {
    my( $self ) = @_;
    
    # Use a slightly smaller font so that more info fits on the screen
    $self->font_size(12);

    my $ss = $self->SequenceSet or confess "No SequenceSet or SequenceNotes attached";
    my $write = $ss->write_access;
    
    my $canvas = $self->canvas;
    my $top = $canvas->toplevel;
    
    my $button_frame = $top->Frame;
    $button_frame->pack(
			-side => 'top',
 			);        
    
    my( $comment, $comment_label, $set );

    if ($write) {             
  	$comment_label = $button_frame->Label(
  					      -text => 'Note text:', # 
  					      );
 	$comment_label->pack(
 			     -side => 'left',
 			     );
 	my $text = '' ;
 	$self->entry_text_ref(\$text ) ;
 	$comment = $button_frame->Entry(
 					-width  => 55,
 					-font   => ['Helvetica', $self->font_size, 'normal'],
 					-textvariable => $self->entry_text_ref ,                   
 					);
 	$comment->pack(
 		       -side => 'left',
 		       );
 	# Remove Control-H binding from Entry
 	$comment->bind(ref($comment), '<Control-h>', '');
 	$comment->bind(ref($comment), '<Control-H>', '');
	
 	$comment->bind('<Return>',  sub { $self->update_db_comment } ); #update_sequence_notes($comment)});
	$comment->bind('<Destroy>', sub { $self = undef });
 	my $update_comment = sub{
 	    $self->update_db_comment;
 	    #update_sequence_notes($comment);
 	};
 	$set = $self->make_button($button_frame, 'Set note', $update_comment, 0);
 	$top->bind('<Control-s>', $update_comment);
 	$top->bind('<Control-S>', $update_comment);
	$set->bind('<Destroy>', sub { $self = undef });
	
 	$self->bind_item_selection($canvas , $comment );
    }
    
    my $next_clone = sub { 
	my $cs_list = $self->get_CloneSequence_list(); 
	my $cur_idx = $self->clone_index();
	$self->clone_index(++$cur_idx) unless $cur_idx + 1 >= scalar(@$cs_list);
	$self->draw();
    };
    my $prev_clone = sub { 
	my $cs_list = $self->get_CloneSequence_list(); 
	my $cur_idx = $self->clone_index();
	$self->clone_index(--$cur_idx) if $cur_idx;
	$self->draw();
    };
    
    my $prev = $self->make_button($button_frame, 'Prev Clone', $prev_clone);
    my $next = $self->make_button($button_frame, 'Next Clone', $next_clone);
    $prev->bind('<Destroy>', sub { $self = undef });
    $next->bind('<Destroy>', sub { $self = undef });
    $self->prev_button($prev);
    $self->next_button($next);
    
    $self->make_button($button_frame, 'Close', sub { $top->withdraw }, 0);
    
    # I think this is already bound..... 
    # It all gets cleared up twice with it.
    # And I think normal behaviour without it.
    $self->bind_close_window($top);
    
    return $self;
}

sub get_rows_list{
    my ($self) = @_ ;         
    print STDERR "Fetching SequenceNotes list...";
    my $clone = $self->current_clone;
    my $note_list = $clone->get_all_SequenceNotes;
    return $note_list;
}  
sub empty_canvas_message{
    my ($self) = @_;
    my $clone = $self->current_clone;
    return "No History for sequence " . $clone->contig_name . "  " . $clone->clone_name;
}

sub column_methods{
    my $self = shift @_ ;
    my $norm = [$self->font, $self->font_size, 'normal'];
    my $bold = [$self->font, $self->font_size, 'bold'];   
    unless(ref($self->{'_column_methods'}) eq 'ARRAY'){
	my $methods =[
		      sub{
			  my $sn = shift;
			  my $time = $sn->timestamp;
			  my( $year, $month, $mday ) = (localtime($time))[5,4,3];
			  my $txt = sprintf "%04d-%02d-%02d", 1900 + $year, 1 + $month, $mday;
			  return { -text => $txt, -font => $norm, -tags => ['searchable']}; 
		      },
		      sub{
			  # Use closure for font definition
			  my $note = shift;
			  my $author = $note->author;
			  return {-text => "$author", -font => $bold, -tags => ['searchable']};
		      },
		      sub{
			  # Use closure for font definition
			  my $note = shift;
			  return {-text => $note->text , -font => $norm, -tags => ['searchable'] };
		      }            
		      ];
	$self->{'_column_methods'} = $methods;
    }
    return $self->{'_column_methods'};
}


sub bind_item_selection{
    my ($self , $canvas , $comment_entry) = @_ ;
    
    $canvas->configure(-selectbackground => 'gold');
    $canvas->CanvasBind('<Button-1>', sub {
	return if $self->delete_message;
	$self->deselect_all_selected_not_current();
	$self->toggle_current;
	$self->get_message;
	if (defined $comment_entry){
	    $comment_entry->focus;
	    my $length  = length($comment_entry->get) ;
	    #$comment_entry->selectionRange(0 , $length );
	    $comment_entry->icursor($length);    
	}
	
    });
    $canvas->CanvasBind('<Destroy>', sub { $self = undef });
    $comment_entry->bind('<Destroy>', sub {$self = undef});
}

sub toggle_selection {
    my( $self, $obj ) = @_;
    
    my $canvas = $self->canvas;
    my $is_selected = grep $_ eq 'selected', $canvas->gettags($obj);
    my( $new_colour ); 
    if ($is_selected) {
	$new_colour = '#ccccff';
	$canvas->dtag($obj, 'selected');
    } else {
	$new_colour = '#ffcccc';
	$canvas->addtag('selected', 'withtag', $obj);
    }
    $canvas->itemconfigure($obj,
			   -fill => $new_colour,
			   );
}

sub get_row_id{
    my ($self) = @_ ;
    my $row_tag = $self->get_current_row_tag or return;
    my ($index) = $row_tag =~ /row=(\d+)/;
    return $index;
}

sub get_message{
    my ($self) = @_ ;
    my ($index) = $self->get_row_id ; 
    my $text = $self->indexed_note_text($index); 
    ${$self->entry_text_ref()} = $text;
}

sub indexed_note_text{
    my ($self , $index , $text) = @_ ;
    return '' unless $index;
    $text = $self->current_clone->get_all_SequenceNotes->[$index]->text ; 
    return $text;
}
    
sub update_db_comment{
    my ( $self) = @_;           
    
    #gets the string from the varibale reference stored
    my $new_string = ${$self->entry_text_ref} ;   
    my $dataset = $self->SequenceSetChooser->DataSet;        
    unless ($dataset){
	warn "no Dataset object for this history window.\nIt is not possible to update the comment.";
	return;
    }
    unless ( $self->selected_CloneSequence_indices){
	$self->message('you need to select a note to update');
	$self->Unbusy;
	return ;
    }
    
    my ($index, @extra_indices) = @{$self->selected_CloneSequence_indices};
    if (@extra_indices > 0){
	# should only be possible to select 1 index on this canvas
	confess "ok we have these rows selected @extra_indices \nsomething wrong there! should only be able to select 1";
    }
    
    $self->Busy;        
    my $clone_sequence      = $self->current_clone ; 
    my $current_seq_note    = $clone_sequence->get_all_SequenceNotes->[$index];
    
    # check that author is valid to update note
    my $note_author     = $current_seq_note->author; 
    my $current_user    =  $dataset->author;
    if ($note_author eq $current_user){     
	
	###confirm that the user wants to update the entry
	my $confirm = $self->canvas->toplevel->messageBox(-title => 'Update Sequence Note', 
							  -message => "Pleas Confirm that you wish to update this note in the database", 
							  -type => 'OKCancel') ;
	return if ( $confirm eq 'Cancel'   );
	
	$current_seq_note->text($new_string); #change text
	my $contig_id = $clone_sequence->contig_id  || confess "no contig_id for this clone_sequence ";
	$clone_sequence->current_SequenceNote($current_seq_note);
	$dataset->update_current_SequenceNote($clone_sequence, $new_string);
	$self->draw;
    }else{
	$self->canvas->toplevel->messageBox(-title => 'Sorry', 
					    -message => "Only the original author, $note_author, can update these comments\nYou are currently logged on as $current_user", 
					    -type => 'OK');          
    }
    $self->Unbusy;
}

sub Busy{   
    my $self= shift ;
    $self->canvas->toplevel->Busy;
};
    
sub Unbusy{ 
    my $self= shift;
    $self->canvas->toplevel->Unbusy;
};
   



sub DESTROY {
    my( $self ) = @_;
    my $idx = $self->clone_index();
    warn "Destroying CanvasWindow::SequenceNotes::History with idx $idx\n";
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes::History

=head1 AUTHOR

Colin Kingswood <email> ck2@sanger.ac.uk

