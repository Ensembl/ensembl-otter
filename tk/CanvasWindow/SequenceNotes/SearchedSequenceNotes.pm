
### CanvasWindow::SequenceNotes::SearchedSequenceNotes

## this module is designed to work the same as the SequenceNotes module, exept that it will display a ResultSet object 
## (which may contain 1 or more SequenceSets) rather than a single sequenceSet object 

package CanvasWindow::SequenceNotes::SearchedSequenceNotes;

use strict;
use Carp;
use base 'CanvasWindow::SequenceNotes';
use CanvasWindow::SequenceNotes::History;
use Data::Dumper ;

sub ResultSet {
    my ($self , $result_set)  = @_;
    
    if (defined $result_set){
        $self->{'result_set'} = $result_set ;
    }
       
    return $self->{'result_set'}  ;
}

sub initialise{
    my ($self) = shift;
    $self->get_CloneSequence_list(1);
    $self->SUPER::initialise(@_);
}

sub get_CloneSequence_list{
    my ($self, $force_update) = @_;

    my $rs = $self->ResultSet();
    my $ss_list = $rs->get_all_SequenceSets();
    my @cs_list;
    foreach my $ss(@$ss_list){
        my $ds = $self->SequenceSetChooser->DataSet();
        $ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
        $ds->status_refresh_for_SequenceSet($ss) if $force_update;
        push(@cs_list, @{$ss->CloneSequence_list});
    }
    return \@cs_list;
}

## needs to refresh each of the sequencesets in the resultset
sub _refresh_SequenceSet{
    my ($self , $col_number) = @_ ;

    unless($col_number){
        # otherwise get_CloneSequence_list gets called multiple times.
        # once per iteration of @{$self->ResultSet->get_all_SequenceSets}
        # see $self->SUPER::_refresh_SequenceSet();
        $self->get_CloneSequence_list(1);
        return undef;
    }

    foreach my $ss (@{$self->ResultSet->get_all_SequenceSets}){
        $self->SequenceSet($ss) ;
        $self->SUPER::_refresh_SequenceSet($col_number);
        $self->{'_SequenceSet'} = undef ;
    }
}

sub save_sequence_notes{
    my ($self, $comment) = @_;
    my ($ss , $index) = $self->get_SequenceSet_index_list_of_selected();
    return unless $ss;
    $self->SequenceSet($ss);
    $self->SUPER::save_sequence_notes($comment);
    $self->{'_SequenceSet'} = undef;
    # this is really slow 
    # SUPER::save_sequence_notes calls draw, 
    # so we draw everything only to refresh the column hmm.
    # Has to be done to re get the sequence notes for other 
    # sequence sets which contain the same clone.
    $self->refresh_column(6);
}

sub _write_access{
    my ($self) = @_ ;
    my $rs = $self->ResultSet or confess "no ResultSet attached" ;
    my $ss =  $rs->get_all_SequenceSets->[0] ;
    return $ss->write_access ;
}


sub draw {
    my( $self ) = @_;

    my $size      = $self->font_size;
    my $canvas    = $self->canvas;
    my $methods   = $self->column_methods;

    my $max_width = $self->max_column_width;

    $canvas->delete('all');

    print STDERR "Drawing list...";
       
    my $norm_font   =  ['Helvetica', $size, 'normal'];
    my $bold        =  ['Helvetica', $size, 'bold'];
    
    my $gap_pos = {};
    
    my $rs   = $self->ResultSet();
    my $list = $rs->matching_assembly_types();

    my $row_tag  = sub { return "row=".shift(@_) };
    my $col_tag  = sub { return "col=".shift(@_) };
    my $cs_tag   = sub { return "cs=".shift(@_)  };
    my $ass_tag  = sub { return "assembly=". shift(@_) };
    my $y_coord  = sub { return $size * shift(@_) };
    my $x_coord  = sub { return $size * shift(@_) };
    my $col_meth = sub { return @{$methods->[shift(@_)]}[0,1] };
    my $add_gap  = sub { $gap_pos->{shift(@_)} = 1 };

    my $row  = 0; # keep track of which row we're on
    # go through each of the assemblies which match
    foreach my $type(@$list){
        my $ss      = $rs->get_SequenceSet_by_name($type);
        my $cs_list = $ss->CloneSequence_list();

        # display a header for the assembly
        $canvas->createText(
                            $x_coord->(1), $y_coord->($row),
                            -anchor => 'nw',
                            -font   => $bold,
                            -tags   => [$row_tag->($row), 'gap_label'],
                            -text   => "Assembly : $type    Chromosome : " . $cs_list->[0]->chromosome->name,
                            );
        $add_gap->($row);
        $row++; # increment the number after drawing this row
        my $prev_cs;
        
        # go through each of the clone sequences for this assembly
        for(my $i = 0; $i < @$cs_list; $i++){
            my $cs = $cs_list->[$i];
            $prev_cs ||= $cs;

            # check for a gap here.
            my $gap_text = '';
            if($prev_cs->chromosome() != $cs->chromosome()){
                $gap_text = "Chromosome : " . $cs->chromosome->name();
            }elsif($cs->can('chr_start')){
                my $gap = $cs->chr_start - $prev_cs->chr_end - 1;
                if($gap > 0){
                    my $gap_size = reverse $gap;
                    $gap_size =~ s/(\d{3})(?=\d)/$1 /g;
                    $gap_size = reverse $gap_size;
                    $gap_text = qq`GAP ($gap_size bp)`;
                }
            }
            $prev_cs = $cs;
            if($gap_text){
                $canvas->createText(
                                    $x_coord->(1), $y_coord->($row),
                                    -anchor => 'nw',
                                    -font   => $bold,
                                    -tags   => [$row_tag->($row), 'gap_label'],
                                    -text   => $gap_text ,
                                    );
                $add_gap->($row);
                $row++;
            }


            # draw each of the columns for this clone sequence
            my $no_cols = scalar(@$methods);
            for (my $col = 0; $col < $no_cols; $col++) { # go through each method
                my ($calling_method, $arg_method) = $col_meth->($col);

                my $opt_hash = $arg_method->($cs, $i , $self) if $arg_method ;
                $opt_hash->{'-anchor'} ||= 'nw';
                $opt_hash->{'-font'}   ||= $norm_font;
                $opt_hash->{'-width'}  ||= $max_width;
                $opt_hash->{'-tags'}   ||= [];
                $opt_hash->{'-fill'}     = 'red' if $cs->is_match && $col == 1;
                push(@{$opt_hash->{'-tags'}}, 
                     $row_tag->($row),
                     $col_tag->($col),
#                     $ass_tag->($type),
                     $cs_tag->($row - scalar(keys(%$gap_pos))));
                
                $calling_method->($canvas,  $x_coord->($col) , $y_coord->($row) ,  %$opt_hash);  ## in most cases $calling_method will be $canvas->createText   
            }
            $self->cs_assembly_lookup($row - scalar(keys(%$gap_pos)), $type);
            warn $cs->accession . " - $type - " . $row_tag->($row) . " - " . $cs_tag->($row - scalar(keys(%$gap_pos))) . " " .$ass_tag->($type)." \n";
            $row++;
        }
    }
    print STDERR " done\n";
    my $col_count = scalar @$methods  + 1; # +1 for the padlock (non text column)

    print STDERR "Laying out table...";
    $self->layout_columns_and_rows($col_count, $row);
    print STDERR " done\n";
    print STDERR "Drawing background rectangles...";
    $self->draw_row_backgrounds($row, $gap_pos);
    print STDERR " done\n";
    $self->message($self->empty_canvas_message) if !$row;
    $self->fix_window_min_max_sizes;
    
}


sub run_lace{
    my ($self) = @_ ;

    ### Prevent opening of sequences already in lace sessions    
    return unless $self->set_selected_from_canvas; # sets the selected clones on the canvas as selected in the ss object!

    my @pair = $self->get_SequenceSet_index_list_of_selected();

    my ($ss, $indices) = @pair;
    my $selected = $ss->selected_CloneSequences();

    my $number_selected = ( $selected ? scalar( @$selected) : 0 )  ;

    next unless $number_selected ;  # dont want to try and open ss with unselected clones
    my @names = map {$_->clone_name}  @{$ss->selected_CloneSequences} ;
    print "@names";
    my $title = $self->selected_sequence_string($ss, $indices);
    $self->_open_SequenceSet($ss, $title);

}
sub cs_assembly_lookup{
    my ($self, $cs_idx, $type) = @_;
    if(defined($cs_idx) && $type){
        $self->{'_cs2assembly'}->{$cs_idx} = $type;
    }
    return $self->{'_cs2assembly'} || {};
}

# sets the CloneSequence list in each SequenceSet object ( cs's selected on the canvas)
sub set_selected_from_canvas{
    my ($self) = @_;
    # this does the work
    my @pair = $self->get_SequenceSet_index_list_of_selected();

    if(scalar(@pair) == 2){
        my ($ss, $allowed_idx) = @pair;
        my $cs_list = $ss->CloneSequence_list();
        my $selected = [ @{$cs_list}[@$allowed_idx] ];
        $ss->selected_CloneSequences($selected);
        return 1;
    }else{
        return 0;
    }
}

# returns the indices of the selected clones
### Nasty code duplication with SequenceNotes
sub popup_missing_analysis {
    my ($self) = @_;
    #my $index = $self->get_current_CloneSequence_index ; 
    my ($ss, $index) = $self->get_SequenceSet_index_of_current;
    unless (defined $index ){
        return;
    }
    unless ( $self->check_for_Status($ss, $index) ){
        # window has not been created already - create one
        my $cs =  $ss->CloneSequence_list->[$index];
        my $top = $self->canvas->Toplevel();
        $top->transient($self->canvas->toplevel);
        my $hp  = CanvasWindow::SequenceNotes::Status->new($top, 650 , 50);
	    # $hp->SequenceNotes($self); # can't have reference to self if we're inheriting
	    # clean up just won't work.
        $hp->SequenceSet($ss);
        $hp->SequenceSetChooser($self->SequenceSetChooser);
        $hp->name($cs->contig_name);
        $hp->initialise;
        $hp->clone_index($index) ;
        $hp->draw;
        $self->add_Status($hp);
    }
}

sub popup_ana_seq_history{
    my ($self) = @_;    
    my ($ss , $index) = $self->get_SequenceSet_index_of_current; 
    
    unless (defined($index)){
        return;
    }
  
    unless ( $self->check_for_History($ss, $index) ){
        # window has not been created already - create one
        my $cs =  $ss->CloneSequence_list->[$index];
        my $clone_list = $cs->get_all_SequenceNotes; 
        if (@$clone_list){
            my $top = $self->canvas->Toplevel();
            $top->transient($self->canvas->toplevel);
            my $hp  = CanvasWindow::SequenceNotes::History->new($top, 650 , 50);  
            $hp->SequenceSet($ss);
            $hp->SequenceSetChooser($self->SequenceSetChooser);
            $hp->name($cs->contig_name);
            $hp->initialise;
            $hp->clone_index($index) ;
            $hp->draw;
            $self->add_History($hp);
        }
        else{
            $self->message( "No History for sequence " . $cs->contig_name . "  " . $cs->clone_name); 
        }
    }  
}

# so we dont bring up copies of the same window
sub check_for_History{
    my ($self , $ss , $index) = @_;
    return 0 unless defined($index); # 0 is valid index

    my $hist_win = $self->{'_History_win'};
    return 0 unless $hist_win;
    $hist_win->clone_index($index);
    $hist_win->SequenceSet($ss);
    $hist_win->draw();
    $hist_win->canvas->toplevel->deiconify;
    $hist_win->canvas->toplevel->raise;
    return 1;
}
# so we dont bring up copies of the same window
sub check_for_Status{
    my ($self, $ss, $index) = @_;

    return unless defined($index); # 0 is valid index

    my $status_win = $self->{'_Status_win'} or return;
    $status_win->clone_index($index);
    $status_win->SequenceSet($ss);
    $status_win->draw();
    $status_win->canvas->toplevel->deiconify;
    $status_win->canvas->toplevel->raise;
    return 1;
}


sub get_SequenceSet_index_of_current{
    my ($self) = @_;
    warn "get_SequenceSet_index_of_current called \n";
    # get the hash to correct the indices from cs=n to indices for each SeqSet
    my $idx_adjust = $self->__index_adjust_hash(); 

    if(defined(my $index = $self->get_current_CloneSequence_index)){
        # this is a lookup between cs=n index and assembly type
        my $lookup = $self->cs_assembly_lookup();
        my $name   = $lookup->{$index};
        my $rs     = $self->ResultSet();
        my $ss     = $rs->get_SequenceSet_by_name($name);        
        my $adjusted_idx = $index - $idx_adjust->{$name};

        warn "Found type '$name' and index $adjusted_idx \n";
        return ($ss, $adjusted_idx);
    }else{
        warn "$self->get_current_CloneSequence_index found nothing\n";
    }
    return ();
}

sub get_SequenceSet_index_list_of_selected{
    my ($self) = @_;
    
    # get the hash to correct the indices from cs= to indices for each SeqSet
    my $idx_adjust = $self->__index_adjust_hash(); 
    
    my $message = '"Nothing is selected"';
    if (my $sel_i = $self->selected_CloneSequence_indices){
        my $first;
        my @allowed_idx = ();
        # lookup between clone seq (cs=n) index and assembly type 
        my $lookup = $self->cs_assembly_lookup();
        foreach my $selected_idx(@$sel_i){
            $first ||= $lookup->{$selected_idx};
            if($first eq $lookup->{$selected_idx}){
                push(@allowed_idx, $selected_idx - $idx_adjust->{$first});
            }else{
                $message = "Please select clones from just one Sequence Set.";
            }
        }
        warn " type $first  - @allowed_idx\n";
        unless($first){
            return $self->message("Error");
            return ();
        }
        my $rs = $self->ResultSet();
        my $ss = $rs->get_SequenceSet_by_name($first);
        unless($ss){
            $self->message("Couldn't find Sequence Set by the name of '$first'.");
            return ();
        }
        return $ss, \@allowed_idx;
    }
    $self->message($message);
    return ();
}


# creates a string based on the selected clones, with commas seperating individual values or dots to represent a continous sequence
sub selected_sequence_string{
    my ($self, @pair) = @_ ;
    
    return "Error getting title" unless @pair == 2;

    my ($ss, $selected) = @pair;

    my $string = "Assembly " . $ss->name ;
    
    my $prev = shift @$selected;
    if (scalar(@$selected) == 0){ 
        $string .= ", clone " . ($prev + 1);
    }
    else{
        $string .= ", clones " . ($prev + 1);
        my $continous = 0 ;

        foreach my $element (@$selected){
            if (($element  eq ($prev + 1))){
                if ($element == $selected->[$#{$selected}]){
                    $string .= (".." . ($element + 1));
                }
                $continous = 1;
            }
            else{                                       
                if ($continous){
                    $string .= (".." . ($prev + 1)) ;
                    $continous = 0;
                }
                $string .= (", " . ($element + 1)) ; 
            }
            $prev = $element ;
        }
    }
    return $string ;
}

sub __index_adjust_hash{
    my $self = shift;
    my $rs   = $self->ResultSet();

    # always get them in this order
    my $all_ss_names = $rs->matching_assembly_types(); 
    my $idx_adjust   = {};
    my $total = 0;
    $idx_adjust->{$all_ss_names->[0]} = 0;
    for(my $i = 1;$i < @$all_ss_names; $i++){
        my $p       = $all_ss_names->[$i-1];
        my $p_count = scalar(@{$rs->get_SequenceSet_by_name($p)->CloneSequence_list()});
        $total     += $p_count;
        $idx_adjust->{$all_ss_names->[$i]} = $total;
    }
    return $idx_adjust;
}

1;
