
### CanvasWindow::SequenceNotes::Status

package CanvasWindow::SequenceNotes::Status;

use strict;
use Carp;
use Data::Dumper;
use base 'CanvasWindow::SequenceNotes';

sub clone_index{
    my ($self, $index) = @_;
    if (defined($index)) {
	    $self->{'_clone_index'} = $index;
	    if ($self->SequenceSet) {
	        my $cs_list = $self->get_CloneSequence_list();
	        my $prev_button = $self->prev_button();
	        my $next_button = $self->next_button();
	        return $index unless $prev_button;
	        if ($index == 0) {
                # First clone
		        $prev_button->configure(-state => 'disabled');
		        $next_button->configure(-state => 'normal');
	        }
            elsif ($index + 1 >= scalar(@$cs_list)) {
                # Last clone
		        $prev_button->configure(-state => 'normal');
		        $next_button->configure(-state => 'disabled');
	        }
            else {
                # Internal clone
		        $prev_button->configure(-state => 'normal');
		        $next_button->configure(-state => 'normal');
	        }
	    }
    }
    return $self->{'_clone_index'};
}

sub next_button {
    my ($self, $next) = @_;
    if ($next){
	    $self->{'_next_button'} = $next;
    }
    return $self->{'_next_button'};
}
sub prev_button {
    my ($self, $prev) = @_;
    if ($prev){
	    $self->{'_prev_button'} = $prev;
    }
    return $self->{'_prev_button'};
}

sub current_clone {
    my ($self , $clone) = @_;
    my $cs_list = $self->get_CloneSequence_list();
    my $cloneSeq = @$cs_list[$self->clone_index];

    my $title = "Pipeline Status for " .$cloneSeq->contig_name . "  " .$cloneSeq->clone_name;
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
    
    # Define how the table gets drawn by supplying a column_methods array
    my $norm = [$self->font, $self->font_size, 'normal'];
    my $bold = [$self->font, $self->font_size, 'bold'];   
    my $status_colors = {'completed'   => 'darkgreen', 
                         'missing'     => 'red', 
                         'unavailable' => 'darkred'};
	my $write_text  = \&CanvasWindow::SequenceNotes::_write_text ;
    $self->column_methods([
        [$write_text, sub{
	         my $pipe_status = shift;
	         return { -font => $bold, -tags => ['searchable'], -text => $pipe_status->{'name'} }; 
	         }],
        [$write_text, sub{
	         my $pipe_status = shift;
             my $status = $pipe_status->{'status'};
	         return { -font => $bold, -tags => ['searchable'], -text => $status, -fill => $status_colors->{$status}};
             }],
        [$write_text, sub{
	         my $pipe_status = shift;
	         return { -font => $bold, -tags => ['searchable'], -text => $pipe_status->{'created'} };
             }],
        [$write_text, sub{
	         my $pipe_status = shift;
	         return { -font => $bold, -tags => ['searchable'], -text => $pipe_status->{'version'} };
             }],
    ]);
    
    return $self;
}

sub get_rows_list {
    my ($self) = @_ ;         

    return $self->current_clone->pipelineStatus->display_list;
}  

sub empty_canvas_message{
    my ($self) = @_;
    my $clone = $self->current_clone;
    return "No Status available for sequence " . $clone->contig_name . "  " . $clone->clone_name;
}


sub bind_item_selection{
    # Called by SequenceNotes->initialise
}

sub toggle_selection {
    my( $self, $obj ) = @_;
    return;
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
#    my $text = $self->indexed_note_text($index); 
#    ${$self->entry_text_ref()} = $text;
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
    warn "Destroying CanvasWindow::SequenceNotes::Status with idx $idx\n";
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes::History

=head1 AUTHOR

Colin Kingswood <email> ck2@sanger.ac.uk

