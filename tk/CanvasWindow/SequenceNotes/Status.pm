
### CanvasWindow::SequenceNotes::Status

package CanvasWindow::SequenceNotes::Status;

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



sub current_clone{
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
    
    return $self;
}

sub get_rows_list{
    my ($self) = @_ ;         
    print STDERR "Fetching SequenceNotes list...";
    my $clone = $self->current_clone;
    my $note_list = [];#$clone->get_all_SequenceNotes;

    my $pipeStatus = $clone->pipelineStatus();
    my $completed  = $pipeStatus->completed();
    foreach my $comp(sort(keys(%{$completed}))){
        push(@$note_list, [ $completed->{$comp}, 'completed' ]);
    }
    my $unfinished = $pipeStatus->unfinished();
    foreach my $unfin(sort(keys(%{$unfinished}))){
        push(@$note_list, [ $unfinished->{$unfin}, 'unfinished' ]);
    }
    return $note_list;
}  
sub empty_canvas_message{
    my ($self) = @_;
    my $clone = $self->current_clone;
    return "No Status available for sequence " . $clone->contig_name . "  " . $clone->clone_name;
}

#already have this method in SequenceNotes.pm, but perl doesnt seem to like inheritance with anonymous subroutines
sub _write_text{
    my ($canvas ,  @args) = @_ ;
    $canvas->createText(@args) ;
}

sub column_methods{
    my $self = shift @_ ;
    my $norm = [$self->font, $self->font_size, 'normal'];
    my $bold = [$self->font, $self->font_size, 'bold'];   
    my $status_colors = {'completed'   => 'darkgreen', 
                         'unfinished'  => 'red', 
                         'unavailable' => 'darkred'};
    unless(ref($self->{'_column_methods'}) eq 'ARRAY'){
	my $calling_method  = \&_write_text ;
        my $methods =[
		      [ $calling_method,
                      sub{
			  my $arr_ref = shift;
			  #my( $year, $month, $mday ) = (localtime($time))[5,4,3];
			  #my $txt = sprintf "%04d-%02d-%02d", 1900 + $year, 1 + $month, $mday;
			  return { -text => $arr_ref->[0]->logic_name, -font => $bold, -tags => ['searchable']}; 
		      }],
                      [$calling_method , 
		      sub{
			  # Use closure for font definition
			  my $arr_ref = shift;
                          my $color = $status_colors->{$arr_ref->[1]};
			  return {-text => $arr_ref->[1], -font => $bold, -tags => ['searchable'], -fill => $color};
		      }],
		      [$calling_method, 
                      sub{
			  # Use closure for font definition
			  my $arr_ref = shift;
			  return {-text => $arr_ref->[0]->created , -font => $norm, -tags => ['searchable'] };
		      }],
		      [$calling_method, 
                      sub{
			  # Use closure for font definition
			  my $arr_ref = shift;
			  return {-text => $arr_ref->[0]->db_version , -font => $norm, -tags => ['searchable'] };
		      }]                        
		      ];
	$self->{'_column_methods'} = $methods;
    }
    return $self->{'_column_methods'};
}


sub bind_item_selection{
    my ($self , $canvas , $comment_entry) = @_ ;
    return;
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

