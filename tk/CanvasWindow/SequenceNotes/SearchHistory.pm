### CanvasWindow::SequenceNotes::SearchHistory.pm

package CanvasWindow::SequenceNotes::SearchHistory ;

use strict ;
 
use base qw(CanvasWindow::SequenceNotes::History CanvasWindow::SequenceNotes::SearchedSequenceNotes) ;


sub get_CloneSequence_list {
    my $self = pop  @_ ;
    
    # want to use the SearchedSequenceNotes version of this method
    # but the inheritance heirarchy will use the SequenceNotes one first (as History inherits from it). 
    my $searched = CanvasWindow::SequenceNotes::SearchedSequenceNotes->can("get_CloneSequence_list") ;  
    return  $self->$searched(@_) ;
}

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

1;
