
### CanvasWindow::SequenceNotes::SearchedSequenceNotes

## this module is designed to work the same as the SequenceNotes module, exept that it will display a ResultSet 
## (which may contain 1 or more SequenceSets )

package CanvasWindow::SequenceNotes::SearchedSequenceNotes;

use strict;
use Carp;
use base 'CanvasWindow::SequenceNotes';
use CanvasWindow::SequenceNotes::SearchHistory ;
use Data::Dumper ;

sub ResultSet {
    my ($self , $result_set)  = @_;
    
    if (defined $result_set){
        $self->{'result_set'} = $result_set ;
    }
       
    return $self->{'result_set'}  ;
}


sub get_CloneSequence_list {
    my( $self , $force ) = @_;

       
    my $rs = $self->ResultSet ;
    my $ss_list = $rs->get_all_SequenceSets ;  
    
    my @cs_list ;
    foreach my $ss (@$ss_list){ 
        my $ds = $self->SequenceSetChooser->DataSet;
        $ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
        push (@cs_list ,  @{$ss->CloneSequence_list});    
    }
    return \@cs_list;
}

## needs to refresh each of the sequencesets in the resultset
sub _refresh_SequenceSet{
    my ($self , $col_number) = @_ ;

    foreach my $ss (@{$self->ResultSet->get_all_SequenceSets}){
        $self->SequenceSet($ss) ;
        $self->SUPER::_refresh_SequenceSet($col_number) ;
        $self->{'_SequenceSet'} = undef ;
    }

}

# returns a list. Each elemnt of the list is an annonymous array with 2 elements.
# the first element is the CloneSequence and the second element is the assembly type
sub get_CloneSequence_list_with_assembly{
    my( $self ) = @_;  
    my $rs = $self->ResultSet ;
    my $ss_list = $rs->get_all_SequenceSets ;  
    
    my @cs_assembly_list ;
    foreach my $ss (@$ss_list){ 
        my $ds = $self->SequenceSetChooser->DataSet;
        $ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
        my $assembly_list = $ss->CloneSequence_list ;
        my @newlist ;
        foreach my $cs ( @$assembly_list) {
            push (@cs_assembly_list ,  [ $cs , $ss->name ] );
        } 
    }
    return \@cs_assembly_list; 
}

sub _write_access{
    my ($self) = @_ ;
    my $rs = $self->ResultSet or confess "no ResultSet attached" ;
    my $ss = pop @{$rs->get_all_SequenceSets} ;
    return $ss->write_access;
}


sub draw {
    my( $self ) = @_;
    
    # gets a list of CloneSequence objects.
    # draws a row for each of them
    
    #my $cs_list   = $self->get_rows_list;
    my $cs_assembly_list = $self->get_CloneSequence_list_with_assembly ;

    print STDERR " done\n";
    my $size      = $self->font_size;
    my $canvas    = $self->canvas;
    my $methods   = $self->column_methods;

    my $max_width = $self->max_column_width;

    $canvas->delete('all');
   

    print STDERR "Drawing list...";
       
    my $prev_assembly = undef ; #$cs_assembly_list->[0]->[1] ;
    my $prev_chr = 'undef' ; #$$cs_assembly_list[0]->[0]->chromosome;
    my $assembly_index = 0 ;
    
    my $norm_font   =  ['Helvetica', $size, 'normal'];
    my $bold        =  ['Helvetica', $size, 'bold'];
    
    my $gaps = 0;
    my $gap_pos = {};
    my $assembly_indices = {} ;
    
    for (my $i = 0; $i < @$cs_assembly_list; $i++) {   # go through each clone sequence
        my $row = $i + $gaps;
        my $cs = $cs_assembly_list->[$i]->[0];
        my $assembly = $cs_assembly_list->[$i]->[1];
        my $row_tag = "row=$row";
        my $y = $row * $size;


        ##
        my $font = $norm_font ;

        my $last = $cs_assembly_list->[$i - 1]->[0];

        my $gap_type = '';
        my $gap = 0;

        ## split up assemblies first
        if ($assembly ne $prev_assembly){
           # put gaps in here
           $gap_type = "Assembly : $assembly    Chromosome : " . $cs->chromosome->name   ;
           $assembly_index = 0 ;
           $prev_assembly = $assembly;
           $prev_chr = $cs->chromosome ;
           $font = $bold;    
        }        
        ## split on chromosomes next
        elsif ($prev_chr != $cs->chromosome ){
            $gap_type = "Chromosome : ". $cs->chromosome->name ;
            $prev_chr = $cs->chromosome ;
        }
        ## split when contigs start doesnt match up with prev contig end
        elsif ($cs->can('chr_start')){
            $gap = $cs->chr_start - $last->chr_end - 1;
            $gap_type = 'Gap' if $gap > 0 ;
        }


        if  ($gap_type =~ /[Assembly||Chromosome||Gap]/  ) {
#            warn "should be creating a gap - gaps $gaps , rows $row";
            $gap_pos->{$row} = 1;              

            my $text ;
            my $gap_size ;

            if ($gap_type eq 'Gap' ){
                $gap_size = reverse $gap;
                $gap_size =~ s/(\d{3})(?=\d)/$1 /g;
                $gap_size = reverse $gap_size;

                $text = "GAP ($gap_size bp)" ;
            }
            else{
                $text = $gap_type
            }            

            $canvas->createText(
                $size, $y,
                -anchor => 'nw',
                -font   => $font,
                -tags   => [$row_tag, 'gap_label'],
                -text   => $text ,
                );
            $gaps++;
            $row++;                
        }

        #--

        $row_tag = "row=$row";
        $y = $row * $size;
        
        my $assembly_tag = "assembly=$assembly" ;
        my $assembly_index_tag = "assembly_index=$assembly_index" ;  # this is the index of the clone relative to the assembl
        $assembly_index ++ ;
        
        for (my $col = 0; $col < @$methods; $col++) { # go through each method
            my $x = $col * $size;

            my $col_tag = "col=$col";
            my $meth_pair = $methods->[$col];
            my $calling_method = @$meth_pair[0]; 
            my $arg_method = @$meth_pair[1] ;
            
	    my $opt_hash = $arg_method->($cs, $i , $self) if $arg_method ;
	    $opt_hash->{'-anchor'} ||= 'nw';
	    $opt_hash->{'-font'}   ||= $norm_font;
	    $opt_hash->{'-width'}  ||= $max_width;
	    $opt_hash->{'-tags'}   ||= [];
	    push(@{$opt_hash->{'-tags'}}, $row_tag, $col_tag, $assembly_tag,  $assembly_index_tag , "cs=$i");
	    
            $calling_method->($canvas,  $x , $y ,  %$opt_hash);  ## in most cases $calling_method will be $canvas->createText   
        } 
    }
    print STDERR " done\n";
    my $col_count = scalar @$methods  + 1; # +1 fopr the padlock (non text column)
    my $row_count = scalar @$cs_assembly_list + $gaps;
    
    print STDERR "Laying out table...";
    $self->layout_columns_and_rows($col_count, $row_count);
    print STDERR " done\n";
    print STDERR "Drawing background rectangles...";
    $self->draw_row_backgrounds($row_count, $gap_pos);
    print STDERR " done\n";
    $self->message($self->empty_canvas_message) unless scalar @$cs_assembly_list;
    $self->fix_window_min_max_sizes;
}


sub run_lace {
    my( $self ) = @_;    
    ### Prevent opening of sequences already in lace sessions
    
    return unless $self->set_selected_from_canvas; # sets the selected clones on the canvas as selected in the ss object!
    my $rs = $self->ResultSet ;
    my $ss_list = $self->selected_SequenceSets ;
    return unless $self->check_for_duplicates($ss_list);
    
    ## going to spawn a new Lace session for each diff SequenceSet    
    foreach my $ss ( @$ss_list){
        my $number_selected = scalar( $ss->selected_CloneSequences) ;
#        warn $ss->name . " number selected $number_selected " ; 
        next unless $number_selected ;  # dont want to try and open ss with unselected clones
           
        my $cl = $self->Client;
        my $title = $self->selected_sequence_string($ss);

        my $db = $self->Client->new_AceDatabase;
        $db->title($title);
        $db->error_flag(1);
        eval{
            $self->init_AceDatabase($db, $ss);
        };
        if ($@) {
            $db->error_flag(0);
            if ($@ =~ /Clones locked/){
                # if our error is because of locked clones, display these to the user
                my $message = "Some of the clones you are trying to open are locked\n";
                my @lines = split /\n/ , $@ ;
                print STDERR $@ ;
                foreach my $line (@lines ){
                    if (my ($clone_name , $author) = $line =~ m/(\S+) has been locked by \'(\S+)\'/ ){            
                        $message  .= "$clone_name is locked by $author \n" ;
                    }
                }
                $self->message( $message  );
            }
            else{
                $self->exception_message($@, 'Error initialising database');
            }
            return;
        }    

        my $xc = $self->make_XaceSeqChooser($title);
        ### Maybe: $xc->SequenceNotes($self);
        $xc->SequenceNotes($self) ;
        $xc->AceDatabase($db);
        my $write_flag = $cl->write_access ? $ss->write_access : 0;
        $xc->write_access($write_flag);  ### Can be part of interface in future
        $xc->Client($self->Client);
        $xc->initialize;
        $self->refresh_column(7) ; # 7 is the locks column
    }
}

# sets the CloneSequence list in each SequenceSet object ( cs's selected on the canvas)
sub set_selected_from_canvas{
    my ($self) = @_ ;

    my $rs = $self->ResultSet;
    my $cs_pair_list = $self->get_CloneSequence_list_with_assembly  ;
    if (my $sel_i = $self->selected_CloneSequence_indices){
        # arrange selected clones by sequence set and store in a hash
        my %selected_hash ;
        my $selected ;
        my $count =  0;
        foreach my $index (@$sel_i ){  
            my $pair = $cs_pair_list->[$index] ;
            my $cs = $pair->[0] ;
            my $ss_name = $pair->[1] ;    
        
            push ( @{ $selected_hash{$ss_name} } , $cs ) ;
        }    
        
        # remove previous selected sequences
        foreach my $ss (@{$rs->get_all_SequenceSets}){
            $ss->unselect_all_CloneSequences ;
        }
        
        # go through each element of the hash and store selected ones in SS object        
        while (my ($cs_name , $selected) = each (%selected_hash)) {
            if ( my $ss = $rs->get_SequenceSet_by_name($cs_name)){
                warn "setting SS now" ;
                $ss->selected_CloneSequences($selected);
            }else{
                confess "Could not find SequenceSet with name $cs_name";
            }
        }
        
        foreach my $ss (@{$rs->get_all_SequenceSets}){
            my $cs_list = $ss->selected_CloneSequences;
            if ($cs_list){
                warn "assembly ". $ss->name . "number selected :" . scalar(@$cs_list) ;
            }
            else{
                warn "nowt selected for " . $ss->name ;
            }
        }
        
        return 1 ;   
    }
    else{
        foreach my $ss (@{$rs->get_all_SequenceSets}){
            $ss->unselect_all_CloneSequences ;
        }
        return 0;    
    }  
}

##returns the indices of the selected clones
sub selected_CloneSequence_indices {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $select = [];
    foreach my $obj ($canvas->find('withtag', 'selected&&clone_seq_rectangle')) {
        my ($i) = map /^cs=(\d+)/, $canvas->gettags($obj);
        unless (defined $i) {
            die "Can't see cs=# in tags: ", join(', ', map "'$_'", $canvas->gettags($obj));
        }
        push(@$select, $i);
    }
    
    if (@$select) {
        return $select;
    } else {
        return;
    }
}
sub popup_missing_analysis{
    my ($self) = @_;
    my $index = $self->get_current_CloneSequence_index ; 
    unless (defined $index ){
        return;
    }
    unless ( $self->check_for_Status($index) ){
        # window has not been created already - create one
        my $cs =  $self->get_CloneSequence_list->[$index];
        my $using_no_pipeline = $cs->pipelineStatus->unavailable();
        if (!$using_no_pipeline){
            my $top = $self->canvas->Toplevel();
            $top->transient($self->canvas->toplevel);
            my $hp  = CanvasWindow::SequenceNotes::Status->new($top, 550 , 50);
	    # $hp->SequenceNotes($self); # can't have reference to self if we're inheriting
	    # clean up just won't work.
            $hp->SequenceSet($self->current_SequenceSet);
            $hp->SequenceSetChooser($self->SequenceSetChooser);
            $hp->name($cs->contig_name);
            $hp->clone_index($index) ;
            $hp->initialise;
            $hp->draw;
            $self->add_Status($hp);
        }
        else{
            $self->message( "You told me not to fetch this information with -nopipeline or pipeline=0." ); 
        }
    }
}
sub popup_ana_seq_history{
    my ($self) = @_;    
    my ($ss , $index) = $self->current_SequenceSet ; 
    
    unless (defined $ss ){
        return;
    }
  
    unless ( $self->check_for_History($ss , $index) ){
        # window has not been created already - create one
        my $cs =  $self->get_CloneSequence_list->[$index];
        my $clone_list = $cs->get_all_SequenceNotes; 
        if (@$clone_list){
            my $top = $self->canvas->Toplevel();
            $top->transient($self->canvas->toplevel);
            my $hp  = CanvasWindow::SequenceNotes::SearchHistory->new($top, 550 , 50);  
            $hp->SequenceSet($ss);
            $hp->ResultSet($self->ResultSet);
            $hp->SequenceSetChooser($self->SequenceSetChooser);
            $hp->name($cs->contig_name);
            $hp->clone_index($index) ;
            $hp->initialise;
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
    return 0 unless defined($ss); # 0 is valid index

    my $hist_win = $self->{'_History_win'};
    return 0 unless $hist_win;
    $hist_win->clone_index($index);
    $hist_win->SequenceSet($ss) ;
    $hist_win->draw();
    $hist_win->canvas->toplevel->deiconify;
    $hist_win->canvas->toplevel->raise;
    return 1;
}


#returns the SequenceSet of the 'current' clone as well as the index of that clone in the SequenceSet
sub current_SequenceSet{
    my ($self ) = @_ ;
    
    # get assembly from tag
    my $canvas = $self->canvas ;
    my ($ss_name , $assem_index);
    # get the selected clone from canvas canvas
    foreach my $obj ($canvas->find('withtag', "current")) {
        my @tags = $canvas->gettags($obj);
        ($ss_name) = map /^assembly=(\S+)/ , @tags;
        ($assem_index) = map /^assembly_index=(\d+)/ , @tags ;
        last if defined $ss_name ;
    }
    return unless defined($ss_name) ; 
   
    # get appropriate SS
    my $ss = $self->ResultSet->get_SequenceSet_by_name($ss_name) ;
    return ($ss , $assem_index ) ;
}


#returns the sequence_sets of the selected clones    
sub selected_SequenceSets{
    my ($self) = @_ ;
    
    my %ss_hash ;
    my @ss_list ;
    
    return unless my $cs_pairs = $self->get_CloneSequence_list_with_assembly ;
    
    foreach my $pair (@$cs_pairs){
        my $assembly_name = $pair->[1] ;
        unless (exists ($ss_hash{$assembly_name})){
            $ss_hash{$assembly_name} = $self->ResultSet->get_SequenceSet_by_name($assembly_name) ;   
        } 
    }
    
    #stick sequence sets in an array
    while (my ($name , $ss) = each (%ss_hash) ) {
        push @ss_list , $ss ;
    }
    
    return \@ss_list ; 
} 


# creates a string based on the selected clones, with commas seperating individual values or dots to represent a continous sequence
sub selected_sequence_string{
    my ($self , $ss) = @_ ;
    
    my $assembly_type = $ss->name ;
    my $canvas = $self->canvas;
    my @selected  ;
    foreach my $obj ($canvas->find('withtag', 'selected&&clone_seq_rectangle')) {

        my ($i ) = map /^row=(\d+)/, $canvas->gettags($obj);
        unless (defined $i) {
            die "Can't see cs=# in tags: ", join(', ', map "'$_'", $canvas->gettags($obj));
        }
        my $ass_index = undef;
        my $ass_type = undef ;

        foreach my $obj2 ( $canvas->find('withtag' , "row=$i&&!clone_seq_rectangle")  ){
            my @tags =  $canvas->gettags($obj2) ;
            last if defined $ass_index ;   
            ($ass_index) = map /^assembly_index=(\d+)/ , $canvas->gettags($obj2) ;
            ($ass_type) = map /^assembly=(\S+)/ , $canvas->gettags($obj2) ;           
        }
        if( ! defined ($ass_index)){
            die "cant find the assembly_index of clone " . ($i + 1) . " in the list" ;
        }
        push(@selected, $ass_index) if $ass_type eq $ss->name;
    }   
    
    my $prev = shift @selected;
    my $string = "Assembly " . $ss->name ;
    
    if (scalar(@selected) == 0){ 
        $string .= ", clone " . ($prev + 1);
    }
    else{
        $string .= ", clones " . ($prev + 1);
        my $continous = 0 ;

        foreach my $element (@selected){
            if (($element  eq ($prev + 1))){
                if ($element == $selected[$#selected]){
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


# checks that the same clone has not been selected twice (as this object may display the same Clone under different assemblies)
# return value of 1 signifies no duplicates;
sub check_for_duplicates{
    my ($self , $ss_list) = @_;
    my %hash ; 
    foreach my $ss ( @$ss_list){          
        my $cs_list = $ss->selected_CloneSequences ;

        foreach my $cs (@$cs_list){
            if (defined $hash{$cs->clone_name}){
                $self->message('You appear to be trying to open the same clone ' . $cs->clone_name . ' on different assemblies. Please select one version to open' );     
                return 0 ;
            }
            else{
                $hash{$cs->clone_name} = $cs ;
            }
        }
    }
    return 1 ;
}


1;
