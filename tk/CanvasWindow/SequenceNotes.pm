
### CanvasWindow::SequenceNotes

package CanvasWindow::SequenceNotes;

use strict;
use Carp;
use base 'CanvasWindow';
use MenuCanvasWindow::XaceSeqChooser;
use CanvasWindow::SequenceNotes::History;
use CanvasWindow::SequenceNotes::Status;
use POSIX qw(ceil);

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub SequenceSet {
    my( $self, $SequenceSet ) = @_;

    if ($SequenceSet) {
        $self->{'_SequenceSet'} = $SequenceSet;
    }
    return $self->{'_SequenceSet'};
}

sub SequenceSetChooser {
    my( $self, $SequenceSetChooser ) = @_;
    
    if ($SequenceSetChooser) {
        $self->{'_SequenceSetChooser'} = $SequenceSetChooser;
    }
    return $self->{'_SequenceSetChooser'};
}

sub get_CloneSequence_list {
    my( $self , $force_update ) = @_;
    
    #if $force_update is set to 1, then it should re-query the db rather than us the old list
    my $ss = $self->SequenceSet;
    my $cs_list = $ss->CloneSequence_list;
    if ($force_update || !$cs_list ) {
        print STDERR "Fetching CloneSequence list...";
        my $ds = $self->SequenceSetChooser->DataSet;
        $ds->fetch_all_CloneSequences_for_SequenceSet($ss);
        $ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
        $ds->status_refresh_for_SequenceSet($ss);
        $cs_list = $ss->CloneSequence_list;
        print STDERR "done\n";
    }
    return $cs_list;
}

## now takes the column number to be refreshed (image or text) and refreshes it
## $i is the row index to start from - allows this method to be used by Searched SequenceNotes
sub refresh_column {
    my ($self, $col_no , $list_pos) = @_ ;
    
    my $canvas = $self->canvas(); 
    my $col_tag = "col=$col_no";
    my $ds = $self->SequenceSetChooser->DataSet();
    my $ss = $self->SequenceSet();
    
    $self->_refresh_SequenceSet($col_no);
    #my $cs_list = $self->get_CloneSequence_list;
    my $cs_list = $self->get_rows_list;
    my $method  = $self->column_methods->[$col_no]->[1];

    for (my $i = 0; $i < @$cs_list; $i++) {

        my $cs = $cs_list->[$i];
        my $tag_string = "$col_tag&&cs=$i";
        if (my ($obj) = $canvas->find('withtag', $tag_string) ) {
	    my $new_content = $method->($cs, $i , $self);
            delete $new_content->{'-tags'};    # Don't want to alter tags
#	    warn "re-configuring column  $col_no , row $i" ; 
            $canvas->itemconfigure($obj, %$new_content);
         } else {
            warn "No object withtag '$tag_string'";
        }
    }
}


# this should be used by the refresh column method
# some of the columns have had different queries written to speed up the refresh ,
# this method activates the appropriate one 
sub _refresh_SequenceSet{
    my ($self , $column_number ) = @_ ;
    $column_number ||= 0;
    my $ds = $self->SequenceSetChooser->DataSet();
    my $ss = $self->SequenceSet;
    if ($column_number == 3){
        # this is the ana_status column - we have a separate (faster) query for this
        $ds->status_refresh_for_SequenceSet($ss);
    }
    elsif($column_number == 7){
        # padlock cloumn - again we have a query for this (hopefully faster also)
        $ds->lock_refresh_for_SequenceSet($ss) ;
    }else{
        # no column number - just update the whole thing
        $self->get_CloneSequence_list(1)
    }
}


# this method returns an anonymous array. Each element of the array consists of another annonymous array of two elements.
# the first of the two elements is the method to be called on the canvas, 
# and the second method that will produce the arguments for the first method
# the first method will _write_text ($canvas->createText) or _draw_image ($canvas->createImage) 
sub column_methods {
    my( $self, $methods ) = @_;
    
    if ($methods) {
        my $ok = 0;
        eval{ $ok = 1 if ref($methods) eq 'ARRAY' };
        confess "Expected array ref but argument is '$methods'" unless $ok;
        $self->{'_column_methods'} = $methods;
    }
    elsif (! $self->{'_column_methods'}) {
        # Setup some default column methods
        my $method = \&_write_text ;   # this is the default method to be used  to display text (rather than drawing s graphic)
        my $draw_method = \&_draw_image ;
        
        my $norm = [$self->font, $self->font_size, 'normal'];
        my $bold = [$self->font, $self->font_size, 'bold'];
        $self->{'_column_methods'} = [
            [$method, \&_column_text_row_number],
            [$method, 
            sub{
                # Use closure for font definition
                my $cs = shift;
                my $acc = $cs->accession;
                my $sv  = $cs->sv;
                return {-text => "$acc.$sv", -font => $bold, -tags => ['searchable']};
            }],
            [$method, 
            sub{
                # Use closure for font definition
                my $cs = shift;
                return {-text => $cs->clone_name, -font => $bold, -tags => ['searchable'] };
            }],
            [$method, \&_column_text_seq_note_status],
	    [$method , 
            sub{
                my $cs = shift;
                if (my $sn = $cs->current_SequenceNote) {
                    my $time = $sn->timestamp;
                    my( $year, $month, $mday ) = (localtime($time))[5,4,3];
                    my $txt = sprintf "%04d-%02d-%02d", 1900 + $year, 1 + $month, $mday;
                    return { -text => $txt, -font => $norm, -tags => ['searchable']};
                } else {
                    return;
                }
            }],
            [$method, \&_column_text_seq_note_author],
            [$method, \&_column_text_seq_note_text],
            [$draw_method ,  \&_padlock_icon ]
            ];
    }
    return $self->{'_column_methods'};
}

sub _write_text{
    my ($canvas ,  @args) = @_ ;
    $canvas->createText(@args) ;
}

sub _draw_image{
    my ($canvas, $x, $y, @args) = @_ ;
    
    ## need to remove some tags -as they are for create_text 
    my %hash = @args ;
    delete $hash{'-width'} ;
    delete $hash{'-font'} ;
    delete $hash{'-anchor'} ; 

    $canvas->createImage($x, $y, %hash , -anchor => 'n');
}

sub _column_text_row_number {
    my( $cs, $row, $self ) = @_;

    my $row_no = ($self->_user_first_clone_seq || 1) + $row;
    return { -text => $row_no };
}

sub _column_text_seq_note_author {
    my( $cs ) = @_;
    
    if (my $sn = $cs->current_SequenceNote) {
        return { -text => $sn->author };
    } else {
        return {};
    }
}

sub _column_text_seq_note_text {
    my( $cs ) = @_;

    if (my $sn = $cs->current_SequenceNote) {
        my $ctg_name = $cs->super_contig_name();
        my $prefix   = ($ctg_name && $ctg_name =~ s/^\*// ? "$ctg_name " : '');
        return { -text => $prefix . $sn->text, -tags => ['searchable']};
    } else {
        return {};
    }
}


sub _column_text_seq_note_status{
    my $cs = shift;
    my $pipeStatus = $cs->pipelineStatus();
    my $text    = $pipeStatus->short_display();
    my $color   = 'darkgreen'; # default color

    
    if($pipeStatus->unavailable()){
        $color = 'blue';
        $text  = '-nopipeline used';
    }else{
        if ($text eq 'missing'){
            my $missing = $pipeStatus->list_unfinished();
            warn $cs->accession . " is missing analyses:\t $missing\n";
            $color   = 'red';
        }
    }

    return {
        -text => $text,
        -fill => $color,
        -tags => ['searchable'],
        };
}

sub max_column_width {
    my( $self, $max_column_width ) = @_;
    
    if ($max_column_width) {
        $self->{'_max_column_width'} = $max_column_width;
    }
    return $self->{'_max_column_width'} || 40 * $self->font_size;
}

sub _write_access{
    my ($self) = @_ ;
    my $ss = $self->SequenceSet or confess "No SequenceSet attached";
    return $ss->write_access;
}


sub initialise {
    my( $self ) = @_;

    # Use a slightly smaller font so that more info fits on the screen
    $self->font_size(12);

#    my $ss     = $self->SequenceSet or confess "No SequenceSet attached";
#    my $write  = $ss->write_access;
    my $write  = $self->Client->write_access;
    my $canvas = $self->canvas;
    my $top    = $canvas->toplevel;
    
    $self->bind_item_selection($canvas);

    $canvas->CanvasBind('<Shift-Button-1>', sub {
        return if $self->delete_message;
        $self->extend_selection;
        });
    $canvas->CanvasBind('<Control-Button-1>', sub {
        return if $self->delete_message;
        $self->toggle_current;
        });

    my ( $comment, $comment_label );
    my ( $button_frame_1, $button_frame_2 );

    if ($write) {
	$button_frame_1 = $top->Frame->pack(-side => 'top');

	$button_frame_2 = $top->Frame->pack(-side => 'top');

	$comment_label = $button_frame_1->Label(-text => 'Note text:',);
	$comment_label->pack(-side => 'left',);
	
	$comment = $button_frame_1->Entry(-width  => 55,
					  -font   => ['Helvetica', $self->font_size, 'normal'],
					  );
	$comment->pack(-side => 'left',);
	
	# Remove Control-H binding from Entry
	$comment->bind(ref($comment), '<Control-h>', '');
	$comment->bind(ref($comment), '<Control-H>', '');
	$button_frame_1->bind('<Destroy>', sub { $self = undef });

	my $set_reviewed = sub{
	    $self->save_sequence_notes($comment);
	};
	$self->make_button($button_frame_2, 'Set note', $set_reviewed, 0);
	$top->bind('<Control-s>', $set_reviewed);
	$top->bind('<Control-S>', $set_reviewed);

    }else{
	$button_frame_2 = $top->Frame->pack(-side => 'top');
        $button_frame_2->Label(-text => 'Read Only   ', 
                               -foreground => 'red')->pack(-side => 'left');
	$button_frame_2->bind('<Destroy>', sub { $self = undef });
    }

    ### Is hunting in CanvasWindow?
    my $hunter = sub{
	$top->Busy;
	$self->hunt_for_selection;
	$top->Unbusy;
    };

    if( @{$self->get_CloneSequence_list()} > $self->max_per_page() ){
        $self->_allow_paging(1);
        my $open_range = sub{
            $top->Busy;
            $self->draw_range();
            $top->Unbusy;
        };
        $self->make_button($button_frame_2, 'Show Range [F7]', $open_range);
        $top->bind('<F7>', $open_range);
    }
    ## First call to this returns empty list!
    #my @all_text_obj = $canvas->find('withtag', 'contig_text');
    
    $self->make_button($button_frame_2, 'Hunt selection', $hunter, 0);
    $top->bind('<Control-h>', $hunter);
    $top->bind('<Control-H>', $hunter);
    
    my $refesher = sub{
	$top->Busy;
	$self->refresh_column(7) ;
        $top->Unbusy;
    };
    $self->make_button($button_frame_2, 'Refresh Locks', $refesher, 0);
    $top->bind('<Control-r>', $refesher);
    $top->bind('<Control-R>', $refesher);
    $top->bind('<F5>',        $refesher);
    
    my $refresh_status = sub {
	$top->Busy;
        $self->_refresh_SequenceSet();
	$self->draw();
	$top->Unbusy;
    };
    $self->make_button($button_frame_2, 'Refresh Ana. Status', $refresh_status, 8);
    $top->bind('<Control-a>', $refresh_status);
    $top->bind('<Control-A>', $refresh_status);
    $top->bind('<F6>',        $refresh_status);
    
    my $run_lace_on_slice = sub{
	$self->slice_window;
    };
    $self->make_button($button_frame_2, 'Open from chr coords', $run_lace_on_slice);
    
    my $run_lace = sub{
	$top->Busy;
	$self->run_lace;
	$top->Unbusy;
    };
    $self->make_button($button_frame_2, 'Run lace', $run_lace, 4);
    $top->bind('<Control-l>', $run_lace);
    $top->bind('<Control-L>', $run_lace);

    #if ($write) {
    #    
    #    my $do_embl_dump = sub{
    #        watch_cursor($top);
    #        my @sequence_name_list = list_selected_sequence_names($canvas);
    #        foreach my $seq (@sequence_name_list) {
    #            do_embl_dump($seq);
    #        }
    #        default_cursor($top);
    #        };
    #    $self->make_button($button_frame2, 'EMBL dump', $do_embl_dump, 0);
    #    $top->bind('<Control-e>', $do_embl_dump);
    #    $top->bind('<Control-E>', $do_embl_dump);
    #}
    
    my $print_to_file = sub {
	$self->page_width(591);
	$self->page_height(841);
	my $title = $top->title;
	$title =~ s/\W+/_/g;
	my @files = $self->print_postscript($title);
	warn "Printed to files:\n",
	map "  $_\n", @files;
    };
    $top->bind('<Control-p>', $print_to_file);
    $top->bind('<Control-P>', $print_to_file);
    
    $canvas->Tk::bind('<Double-Button-1>',  sub{ $self->popup_ana_seq_history });
    $canvas->Tk::bind('<Button-3>',  sub{ $self->popup_missing_analysis });
    
    
    my $close_window = $self->bind_close_window($top);

    # close window button in second button frame
    $self->make_button($button_frame_2, 'Close', $close_window , 0);
    
    return $self;
}

sub bind_close_window{
    my ($self , $top)  = @_ ;
    
    my $close_window = sub{ 
	# This removes the seqSetCh.
	# It must be reset by seqSetCh. when the cached version
	# of this object is deiconified [get_SequenceNotes_by_name in ssc]!!!!
	# not necessary ATM.
	# $self->clean_SequenceSetChooser(); 
	my $top = $self->canvas->toplevel;
	$top->withdraw;
    };
    $top->protocol('WM_DELETE_WINDOW', $close_window);
    $top->bind('<Control-w>',          $close_window);
    $top->bind('<Control-W>',          $close_window);
    $top->bind('<Destroy>',            sub { $self = undef; });

    return $close_window;
}


sub bind_item_selection{
    my ($self , $canvas) = @_ ;
    
    $canvas->configure(-selectbackground => 'gold');
    $canvas->CanvasBind('<Button-1>', sub {
        return if $self->delete_message;
        $self->deselect_all_selected_not_current();
        $self->toggle_current;
        });
    # needs to bind destroy so everyhting gets cleaned up.
    $canvas->CanvasBind('<Destroy>', sub { $self = undef} );
}



sub make_matcher {
    my( $self, $str ) = @_;
    
    # Escape non word characters
    $str =~ s{(\W)}{\\$1}g;
    
    return qr/($str)/i;
}

sub hunt_for_selection {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    
    my( $query_str );
    eval {
        $query_str = $canvas->SelectionGet;
    };
    return if $@;
    #warn "Looking for '$query_str'";
    my $matcher = $self->make_matcher($query_str);
    
    my $current_obj;
    foreach my $obj ($canvas->find('withtag', 'selected')) {
        $current_obj ||= $obj;
        toggle_selection($self, $obj);
    }
    
    my $selected_text_obj = $canvas->selectItem;

    
    # naff hack to get round the error when the first call produces no results.
    my @all_text_obj ;
    for (my $number = 0 ; $number < 2 ; $number ++ ){
        @all_text_obj = $canvas->find('withtag', 'searchable');
        last if @all_text_obj > 0 ; 
    }
    
    unless (@all_text_obj) {
        ### Sometimes a weird error occurs where the first call to find
        ### doesn't return anything - warn user if this happens. 
        $self->message('No searchable text on canvas - is it empty?');
        return;
    }
    
    if ($selected_text_obj) {
        if ($selected_text_obj == $all_text_obj[$#all_text_obj]) {
            # selected obj is last on list, so is to leave at end
        } else {
            for (my $i = 0; $i < @all_text_obj; $i++) {
                if ($all_text_obj[$i] == $selected_text_obj) {
                    my @tail = @all_text_obj[$i + 1 .. $#all_text_obj];
                    my @head = @all_text_obj[0 .. $i];
                    @all_text_obj = (@tail, @head);
                    last;
                }
            }
        }
    }

    my $found = 0;
    foreach my $obj (@all_text_obj) {
        my $text = $canvas->itemcget($obj, 'text');
        #warn "matching $text against $matcher\n";
        if (my ($hit) = $text =~ /$matcher/) {
            $canvas->selectClear;
            my $start = index($text, $hit);
            die "Can't find '$hit' in '$text'" if $start == -1;
            $canvas->selectFrom($obj, $start);
            $canvas->selectTo  ($obj, $start + length($hit) - 1);
            $found = $obj;
            last;
        }
    }
    
    unless ($found) {
        $self->message("Can't find '$query_str'");
        return;
    }
    
    $self->scroll_to_obj($found);
    
    my @overlapping = $canvas->find('overlapping', $canvas->bbox($found));
    foreach my $obj (@overlapping) {
        my @tags = $canvas->gettags($obj);
        if (grep $_ eq 'clone_seq_rectangle', @tags) {
            unless (grep $_ eq 'selected', @tags) {
                toggle_selection($self, $obj);
            }
        }
    }
}

sub make_button {
    my( $self, $parent, $label, $command, $underline_index ) = @_;
    
    my @args = (
	-text => $label,
	-command => $command,
	);
    push(@args, -underline => $underline_index) 
	if defined $underline_index;
    my $button = $parent->Button(@args);
    $button->pack(
	-side => 'left',
	);

    return $button;
}

sub set_selected_from_canvas {
    my( $self ) = @_;
    
    my $ss = $self->SequenceSet;
    if (my $sel_i = $self->selected_CloneSequence_indices) {
        my $cs_list = $ss->CloneSequence_list;
        my $selected = [ @{$cs_list}[@$sel_i] ];
        $ss->selected_CloneSequences($selected);
        return 1;
    } else {
        $ss->unselect_all_CloneSequences;
        return 0;
    }
}

sub run_lace{
    my ($self) = @_ ;
    
    ### Prevent opening of sequences already in lace sessions
    return unless $self->set_selected_from_canvas;
    my $ss = $self->SequenceSet;
    my $title = 'lace '. $self->name . $self->selected_sequence_string;
    $self->_open_SequenceSet($ss , $title) ;
}
sub run_lace_on_slice{
    my ($self) = @_;
    
    ### doing the same as set_selected_from_canvas
    ### but from the user input instead
    my $ss    = $self->SequenceSet;
    my $start = ${$self->slice_min_ref};
    my $end   = ${$self->slice_max_ref};

    my $selected = [];

    if ($start && $end) {
        ($start, $end) = ($end, $start) if $start > $end;
        my $cs_list = $ss->CloneSequence_list;
        my @selection = ();
        for my $i(0..scalar(@$cs_list)-1){
            my $cs = $cs_list->[$i];
            my $cur_s = $cs->chr_start;
            my $cur_e = $cs->chr_end;
            my $minOK = $cur_e >= $start || 0;
            my $maxOK = $cur_s <= $end   || 0;
            my $both  = $minOK & $maxOK;
            warn "Comparing $cur_s to (<) $end and $cur_e to (>) $start, Found: $minOK, $maxOK, $both \n";
            push(@selection, $i) if $both;                                      
        }
        $selected = [ @{$cs_list}[@selection] ];
    }
    if(@$selected){
        $ss->selected_CloneSequences($selected);
    } else {
        $ss->unselect_all_CloneSequences;
        return;
    }
    my $title = qq`lace for SLICE $start - $end ` . $self->name;
    $self->_open_SequenceSet($ss, $title);
}
## allows Searched SequenceNotes.pm to inherit the main part of the run_lace method
sub _open_SequenceSet{
    my ($self , $ss , $title) = @_ ;
        
    my $cl = $self->Client;
#    my $title = $self->selected_sequence_string($ss);

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

# creates a string based on the selected clones, with commas seperating individual values or dots to represent a continous sequence
sub selected_sequence_string{
    my ($self ) = @_ ;
    
    my $selected = $self->selected_CloneSequence_indices;
   
    my $prev = shift @$selected;
    my $string;
    
    if (scalar(@$selected) == 0){ 
        $string = ", clone " . ($prev + 1);
    }
    else{
        $string = ", clones " . ($prev + 1);
        my $continous = 0 ;

        foreach my $element (@$selected){
            if (($element  eq ($prev + 1))){
                if ($element == $selected->[$#$selected]){
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




sub init_AceDatabase {
    my( $self, $db, $ss ) = @_;
    
    $db->make_database_directory;
    $db->write_otter_acefile($ss);
    $db->write_pipeline_data($ss);
    $db->write_ensembl_data($ss);
    $db->initialize_database;
}

sub make_XaceSeqChooser {
    my( $self, $title ) = @_;
    
    my $top = $self->canvas->Toplevel(
        -title  => $title,
        );
    my $xc = MenuCanvasWindow::XaceSeqChooser->new($top);
    return $xc;
}


## this returns the rows to be displayed - havent used get_CloneSequence_list directly, as this allows for easier inheritence of the module
sub get_rows_list{
    my ($self) = @_;
    my $cs_list = $self->get_CloneSequence_list;
    my $max_cs_list = scalar(@$cs_list);

    if($self->_allow_paging()){
        my ($offset, $length) = $self->_sanity_check_paging($max_cs_list);
        warn "slice $offset .. $length\n";
        $cs_list = [ @{ $cs_list } [$offset..$length] ];
    }
    return $cs_list;
}
sub _sanity_check_paging{
    my ($self, $max) = @_;
    $max--;
    my $slice_a = $self->_user_first_clone_seq() - 1;
    my $slice_b = $self->_user_last_clone_seq()  - 1;
    my $max_pp  = $self->max_per_page()          - 1;
    my $sanity_saved = 0;

    if($slice_a < 0){
        $sanity_saved = 1;
        $slice_a      = 0;
    }
    if($slice_b > $max){
        $sanity_saved = 1;
        $slice_b      = $max;
    }
    if($slice_a > $slice_b){
        $sanity_saved        = 1;
        ($slice_a, $slice_b) = (0, $max_pp);
    }
    $self->_user_first_clone_seq($slice_a + 1);
    $self->_user_last_clone_seq($slice_b + 1);    
    $self->max_per_page($slice_b - $slice_a + 1) unless $sanity_saved;
    
    return ($slice_a, $slice_b);
}
sub _user_first_clone_seq{
    my ($self, $min) = @_;
    if(defined($min)){
        $min =~ s/\D//g;
        $self->{'_user_min_element'} = $min;
    }
    return $self->{'_user_min_element'} || 0;
}
sub _user_last_clone_seq{
    my ($self, $max) = @_;
    if(defined($max)){
        $max =~ s/\D//g;
        $self->{'_user_max_element'} = $max;
    }
    return $self->{'_user_max_element'} || 1;
}
sub max_per_page{
    my ($self, $max) = @_;
    $self->{'_max_per_page'} = $max if $max;
    return $self->{'_max_per_page'} || 100;
}
sub draw_paging_buttons{
    my ($self) = @_;
    return () unless $self->_allow_paging();

    my $cur_min = $self->_user_first_clone_seq();
    my $cur_max = $self->_user_last_clone_seq();
    my $abs_max = scalar(@{$self->get_CloneSequence_list()});
    my $ppg_max = $self->max_per_page();

    my $prev_new_min = ($cur_min > 0        ? $cur_min - $ppg_max : 0);
    my $next_new_max = ($cur_max < $abs_max ? $cur_max + $ppg_max : $abs_max);
    my $prev_new_max = $cur_min - 1;
    my $next_new_min = $cur_max + 1;
    
    my $prev_state   = ($cur_min - $ppg_max > 0 ? 'normal' : 'disabled');
    my $next_state   = ($cur_max < $abs_max     ? 'normal' : 'disabled');

    my $t = ceil( $abs_max / $ppg_max );
    my $n = ceil( $cur_min / $ppg_max );

    return () if $prev_state eq 'disabled' && $next_state eq 'disabled';

    my $canvas   = $self->canvas();
    my $pg_frame = $canvas->Frame(-background => 'white');

    my $top  = $canvas->toplevel();

    my $prev_cmd = sub{
        $self->_user_first_clone_seq($prev_new_min);
        $self->_user_last_clone_seq($prev_new_max);
        $self->draw();
    };
    my $next_cmd = sub{ 
        $self->_user_first_clone_seq($next_new_min);
        $self->_user_last_clone_seq($next_new_max);
        $self->draw();
    };
    $top->bind('<Control-Shift-Key-space>', ($prev_state eq 'normal' ? $prev_cmd : undef));
    $top->bind('<Control-Key-space>', ($next_state eq 'normal' ? $next_cmd : undef));
    
    my $prev = $pg_frame->Button(-text => 'prev',
                                 -state => $prev_state,
                                 -command => $prev_cmd
                                 )->pack(
                                         -side  => 'left'
                                         );
    my $mssg = $pg_frame->Label(-text => #"You are viewing a paged display of this sequence set. "
                                "Page $n of $t",
                                -justify => 'center',
                                -background => 'white',
                                )->pack(-side   => 'left',
                                        -fill   => 'x',
                                        -expand => 1);
    my $next = $pg_frame->Button(-text => 'next',
                                 -state => $next_state,
                                 -command => $next_cmd
                                 )->pack(
                                         -side  => 'right'
                                         );
    my @bbox  = $canvas->bbox('all');
    my $x     = $self->font_size();
    my $y     = $bbox[3] + $x;
    my $width = $bbox[2] - $x;
    
    $self->canvas->createWindow($x, $y,
                                -width  => $width,
                                -anchor => 'nw',
                                -window => $pg_frame);
}

sub draw_range{
    my ($self) = @_;
    my $cs_list = $self->get_CloneSequence_list;
    my $no_of_cs = scalar(@$cs_list);

    unless($self->_allow_paging()){
        $self->_user_first_clone_seq(1);
        $self->_user_last_clone_seq($no_of_cs);
        return $self->draw();
    }

    my $trim_window = $self->{'_trim_window'}; 

    $self->_user_first_clone_seq(1);
    $self->_user_last_clone_seq($self->max_per_page);

    unless (defined ($trim_window)){
        ## make a new window
        my $master = $self->canvas->toplevel;
        $master->withdraw(); # only do this first time.
        $trim_window = $master->Toplevel(-title => 'Open Range');
        $trim_window->transient($master);
        $trim_window->protocol('WM_DELETE_WINDOW', sub{ $trim_window->withdraw });
    
        my $label = $trim_window->Label(-text => "It looks as though you are about to open" .
                                        " a large sequence set. Would you like to restrict" .
                                        " the number of clones visible in the ana_notes window?" .
                                        " If so please enter the number of the first and last" .
                                        " clones you would like to see.",
                                        -wraplength => 400, ####????
                                        -justify    => 'center'
                                        )->pack(-side   =>  'top');
        
        my $entry_frame = $trim_window->Frame()->pack(-side   =>  'top',
                                                      -pady   =>  5,
                                                      -fill   =>  'x'
                                                      ); 
        my $label1 = $entry_frame->Label(-text => "First Clone: (1)"
                                         )->pack(-side   =>  'left');
        my $search_entry1 = $entry_frame->Entry(
                                                -width        => 5,
                                                -relief       => 'sunken',
                                                -borderwidth  => 2,
                                                -textvariable => \ ($self->{'_user_min_element'}),
                                               )->pack(-side => 'left',
                                                       -padx => 5,
                                                       -fill => 'x'
                                                       );
        my $label2 = $entry_frame->Label(-text => "Last Clone: ($no_of_cs)"
                                         )->pack(
                                                 -side   =>  'left'
                                                 );
        my $search_entry2 = $entry_frame->Entry(-width        => 5,
                                                -relief       => 'sunken',
                                                -borderwidth  => 2,
                                                -textvariable => \ ($self->{'_user_max_element'}),
                                                )->pack(-side => 'left',
                                                        -padx => 5,
                                                        -fill => 'x',
                                                        );
        ## search cancel buttons
        my $limit_cancel_frame = $trim_window->Frame()->pack(-side => 'bottom',
                                                                     -padx =>  5,
                                                                     -pady =>  5,
                                                                     -fill => 'x'
                                                                     );   
        my $limit_button = $limit_cancel_frame->Button(-text => 'Open Range',
                                                       -command =>  sub{ 
                                                           $trim_window->withdraw();
                                                           $master->deiconify();
                                                           $master->raise();
                                                           $master->focus();
                                                           $self->draw();
                                                       }
                                                       )->pack(
                                                               -side  => 'right'
                                                               );
        my $cancel_button = $limit_cancel_frame->Button(-text    => 'Open All',
                                                        -command => sub { 
                                                            $trim_window->withdraw();
                                                            $self->_user_first_clone_seq(0);
                                                            $self->_user_last_clone_seq($no_of_cs);
                                                            $master->deiconify();
                                                            $master->raise();
                                                            $master->focus();
                                                            $self->draw();
                                                            }
                                                        )->pack(
                                                                -side => 'right'
                                                                );
        $self->{'_trim_window'} = $trim_window;
        $trim_window->bind('<Destroy>' , sub { $self = undef }  ) ;
    }
    
    $trim_window->deiconify;
    $trim_window->raise;
    $trim_window->focus;
    return 1;
}

sub _allow_paging{
    my $self = shift;
    $self->{'_allow_paging'} = shift if @_;
    return ($self->{'_allow_paging'} ? 1 : 0);
}

sub draw {
    my( $self ) = @_;
    # gets a list of CloneSequence objects.
    # draws a row for each of them
    my $cs_list   = $self->get_rows_list;

    my $size      = $self->font_size;
    my $canvas    = $self->canvas;
    my $methods   = $self->column_methods;

    my $max_width = $self->max_column_width;

    $canvas->delete('all');
    my $helv_def = ['Helvetica', $size, 'normal'];

    print STDERR "Drawing list...";
    my $gaps = 0;
    my $gap_pos = {};
    
    for (my $i = 0; $i < @$cs_list; $i++) {   # go through each clone sequence
        my $row = $i + $gaps;
        my $cs = $cs_list->[$i];
        my $row_tag = "row=$row";
        my $y = $row * $size;

        unless ($i == 0) {
            my $last = $cs_list->[$i - 1];
            
            my $gap = 0; # default for non SequenceNotes methods inheriting this method
            #if ($cs->can('chr_start')){
            if (UNIVERSAL::can($cs,'chr_start')){
                $gap = $cs->chr_start - $last->chr_end - 1;
            }            
            if ($gap > 0) {
                $gap_pos->{$row} = 1;              
                # Put spaces between thousands in gap length
                my $gap_size = reverse $gap;
                $gap_size =~ s/(\d{3})(?=\d)/$1 /g;
                $gap_size = reverse $gap_size;
                
                $canvas->createText(
                    $size, $y,
                    -anchor => 'nw',
                    -font   => $helv_def,
                    -tags   => [$row_tag, 'gap_label'],
                    -text   => "GAP ($gap_size bp)",
                    );
                $gaps++;
                $row++;
            }
        }

        $row_tag = "row=$row";
        $y = $row * $size;
        
        for (my $col = 0; $col < @$methods; $col++) { # go through each method
            my $x = $col * $size;

            my $col_tag = "col=$col";
            my $meth_pair = $methods->[$col];
            my $calling_method = @$meth_pair[0]; 
            my $arg_method = @$meth_pair[1] ;
            
	    my $opt_hash =  $arg_method->($cs, $i ,  $self ) if $arg_method ;
            $opt_hash->{'-anchor'} ||= 'nw';
	    $opt_hash->{'-font'}   ||= $helv_def;
	    $opt_hash->{'-width'}  ||= $max_width;
	    $opt_hash->{'-tags'}   ||= [];
	    push(@{$opt_hash->{'-tags'}}, $row_tag, $col_tag, "cs=$i");
	    
            $calling_method->($canvas,  $x , $y ,  %$opt_hash);  ## in most cases this will be $canvas->createText
            
        }
        
    }
    print STDERR " done\n";
    my $col_count = scalar @$methods  + 1; # +1 fopr the padlock (non text column)
    my $row_count = scalar @$cs_list + $gaps;
    
    print STDERR "Laying out table...";
    $self->layout_columns_and_rows($col_count, $row_count);
    print STDERR " done\n";
    print STDERR "Drawing background rectangles...";
    $self->draw_row_backgrounds($row_count, $gap_pos);
    print STDERR " done\n";

    $self->draw_paging_buttons();

    $self->message($self->empty_canvas_message) unless scalar @$cs_list;
    $self->fix_window_min_max_sizes;
    return 0;
}



sub deselect_all_selected_not_current {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    $canvas->selectClear;
    foreach my $obj ($canvas->find('withtag', 'selected&&!current')) {
        $self->toggle_selection($obj);
    }    
}

sub toggle_current {
    my( $self ) = @_;
    
    my $row_tag = $self->get_current_row_tag or return;

    my ($rect) = $self->canvas->find('withtag', "$row_tag&&clone_seq_rectangle") or return;        
    $self->toggle_selection($rect);
}

sub extend_selection {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $row_tag = $self->get_current_row_tag or return;
    my ($current_row) = $row_tag =~ /row=(\d+)/;
    die "Can't parse row number from '$row_tag'" unless defined $current_row;
    
    # Get a list of all the rows that are currently selected
    my( @sel_rows );
    foreach my $obj ($canvas->find('withtag', 'selected&&clone_seq_rectangle')) {
        my ($row) = map /^row=(\d+)/, $canvas->gettags($obj);
        unless (defined $row) {
            die "Can't see row=# in tags: ", join(', ', map "'$_'", $canvas->gettags($obj));
        }
        push(@sel_rows, $row);
    }
    
    my( @new_select, %is_selected );
    if (@sel_rows) {
        %is_selected = map {$_, 1} @sel_rows;

        # Find the row closest to the current row
        my( $closest, $distance );
        foreach my $row (sort @sel_rows) {
            my $this_distance = $current_row < $row ? $row - $current_row : $current_row - $row;
            if (defined $distance) {
                next unless $this_distance < $distance;
            }
            $closest  = $row;
            $distance = $this_distance;
        }

        # Make a list of all the new rows to select between the current and closest selected
        if ($current_row < $closest) {
            @new_select = ($current_row .. $closest);
        } else {
            @new_select = ($closest .. $current_row);
        }
    } else {
        @new_select = ($current_row);
    }
    
    
    # Select all the rows in the new list that are not already selected
    foreach my $row (@new_select) {
        next if $is_selected{$row};
        if (my ($rect) = $canvas->find('withtag', "row=$row&&clone_seq_rectangle")) {
            $self->toggle_selection($rect);
        }
    }
}

sub selected_CloneSequence_indices {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $select = [];
    my $first = $self->_user_first_clone_seq() || 1;
    foreach my $obj ($canvas->find('withtag', 'selected&&clone_seq_rectangle')) {
        my ($i) = map /^cs=(\d+)/, $canvas->gettags($obj);
        unless (defined $i) {
            die "Can't see cs=# in tags: ", join(', ', map "'$_'", $canvas->gettags($obj));
        }
        push(@$select, $i + $first - 1);
    }
    
    if (@$select) {
        return $select;
    } else {
        return;
    }
}

sub get_current_CloneSequence_index {
    my $self = shift @_ ;
    my $canvas = $self->canvas;
    my ($obj) = $canvas->find('withtag', 'current') or return;
     
    my ($i) = map /^cs=(\d+)/, $canvas->gettags($obj);  
    return $i;

}

sub get_current_row_tag {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my ($obj) = $canvas->find('withtag', 'current') or return;

    my( $row_tag );
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^row=/) {
            $row_tag = $tag;
            last;
        }
    }
    return $row_tag;
}

sub toggle_selection {
    my( $self, $obj ) = @_;
    
    my $canvas = $self->canvas;
    my $is_selected = grep $_ eq 'selected', $canvas->gettags($obj);
    my( $new_colour ); 
    if ($is_selected) {
        $new_colour = '#aaaaff';
        $canvas->dtag($obj, 'selected');
    } else {
        $new_colour = '#ffcccc';
        $canvas->addtag('selected', 'withtag', $obj);
    }
    $canvas->itemconfigure($obj,
        -fill => $new_colour,
        );
}

sub draw_row_backgrounds {
    my( $self, $row_count, $gap_pos ) = @_;
    
    my $canvas = $self->canvas;
    my ($x1, $x2) = ($canvas->bbox('all'))[0,2];
    my  ($scroll_x2, $scroll_y)  = $self->initial_canvas_size;
    $x2 = $scroll_x2 if $scroll_x2 > ($x2||0);
    $x1--; $x2++;
    my $cs_i = 0;
    for (my $i = 0; $i < $row_count; $i++) {
        # Don't draw a rectangle behind gaps
        next if $gap_pos->{$i};
        
        my $row_tag = "row=$i";
        my ($y1, $y2) = ($canvas->bbox($row_tag))[1,3];
        $y1--; $y2++;
        my $rec = $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill       => '#ccccff',
            -outline    => undef,
            -tags       => [$row_tag, 'clone_seq_rectangle', "cs=$cs_i"],
            );
        $canvas->lower($rec, $row_tag);
        $cs_i++;
    }
}

my $count ;
sub layout_columns_and_rows {
    my( $self, $max_col, $max_row ) = @_;

    if (defined $count)  { ($count ++ )} else { $count  = 0};
    
    my $canvas = $self->canvas;
    $canvas->delete('clone_seq_rectangle');
    my $size   = $self->font_size;
    
    # Put the columns in the right place
    my $x = $size;
    my $x_pad = int $size * 1.5;
    for (my $c = 0; $c < $max_col; $c++) {
        my $col_tag = "col=$c";
        my ($x1, $x2) = ($canvas->bbox($col_tag))[0,2];
        my $x_shift = $x - ($x1 || 0);
        $canvas->move($col_tag, $x_shift, 0);
        $x = ($x2||0) + $x_shift + $x_pad;
    }
    
    # Put the rows in the right place
    my $y = $size;
    my $y_pad = int $size * 0.5;
    for (my $r = 0; $r < $max_row; $r++) {
        my $row_tag = "row=$r";
        
        my ($y1, $y2) = ($canvas->bbox($row_tag))[1,3];
        
        my $y_shift = $y - $y1;
        $canvas->move($row_tag, 0, $y_shift);
        $y = $y2 + $y_shift + $y_pad;
    }
}

sub save_sequence_notes {
    my( $self, $comment ) = @_;

    my $text = $comment->get;
    $text =~ s/\s/ /g;
    $text =~ s/\s+$//;
    $text =~ s/^\s+//;
    unless ($self->set_selected_from_canvas) {
        $self->message("No clones selected");
        return;
    }
    my $ds = $self->SequenceSetChooser->DataSet;
    my $note = Bio::Otter::Lace::SequenceNote->new;
    $note->text($text);
    $note->author($self->Client->author);
    my $seq_list = $self->SequenceSet->selected_CloneSequences;
    
    $ds->save_author_if_new($self->Client);
    
    foreach my $sequence (@$seq_list) {
        $sequence->add_SequenceNote($note);    
        $sequence->current_SequenceNote($note);
        $ds->save_current_SequenceNote_for_CloneSequence($sequence );
    } 
    $self->draw;
    $self->set_scroll_region_and_maxsize;
}


sub DESTROY {
    my( $self ) = @_;
    my ($type) = ref($self) =~ /([^:]+)$/;
    my $name = $self->name;
    warn "Destroying $type $name\n";
}


sub popup_missing_analysis{
    my ($self) = @_;
    my $index = $self->get_current_CloneSequence_index ; 
    unless (defined $index ){
        return;
    }
    $index += $self->_user_first_clone_seq() - 1;
    unless ( $self->check_for_Status($index) ){
        # window has not been created already - create one
        my $cs =  $self->get_CloneSequence_list->[$index];
        my $using_no_pipeline = $cs->pipelineStatus->unavailable();
        if (!$using_no_pipeline){
            my $top = $self->canvas->Toplevel();
            $top->transient($self->canvas->toplevel);
            my $hp  = CanvasWindow::SequenceNotes::Status->new($top, 650 , 50);
	    # $hp->SequenceNotes($self); # can't have reference to self if we're inheriting
	    # clean up just won't work.
            $hp->SequenceSet($self->SequenceSet);
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
    my $index = $self->get_current_CloneSequence_index ; 
    unless (defined $index ){
        return;
    }
    $index += $self->_user_first_clone_seq() - 1;
    unless ( $self->check_for_History($index) ){
        # window has not been created already - create one
        my $cs =  $self->get_CloneSequence_list->[$index];
        my $clone_list = $cs->get_all_SequenceNotes;
        if (@$clone_list){
            my $top = $self->canvas->Toplevel();
            $top->transient($self->canvas->toplevel);
            my $hp  = CanvasWindow::SequenceNotes::History->new($top, 650 , 50);
	    # $hp->SequenceNotes($self); # can't have reference to self if we're inheriting
	    # clean up just won't work.
            $hp->SequenceSet($self->SequenceSet);
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
sub add_Status{
    my ($self , $status) = @_ ;
    #add a new element to the hash
    if ($status){
	$self->{'_Status_win'} = $status;
    }
    return $self->{'_Status_win'};
}
sub add_History{
    my ($self , $history) = @_ ;
    #add a new element to the hash
    if ($history){
	$self->{'_History_win'} = $history;
    }
    return $self->{'_History_win'};
}

# so we dont bring up copies of the same window
sub check_for_History{
    my ($self , $index) = @_;
    return 0 unless defined($index); # 0 is valid index

    my $hist_win = $self->{'_History_win'};
    return 0 unless $hist_win;
    $hist_win->clone_index($index);
    $hist_win->draw();
    $hist_win->canvas->toplevel->deiconify;
    $hist_win->canvas->toplevel->raise;
    return 1;
}
# so we dont bring up copies of the same window
sub check_for_Status{
    my ($self , $index) = @_;
    return 0 unless defined($index); # 0 is valid index

    my $status_win = $self->{'_Status_win'};
    return 0 unless $status_win;
    $status_win->clone_index($index);
    $status_win->draw();
    $status_win->canvas->toplevel->deiconify;
    $status_win->canvas->toplevel->raise;
    return 1;
}

sub empty_canvas_message{
    return "No Clone Sequences found";
}


sub _padlock_icon{
    my ($cs ,$i ,  $self) = @_ ;

    my( $pixmap );
    if ($cs->get_lock_status){
        $pixmap = $self->closed_padlock_pixmap()  ;
    }
    else{
        $pixmap = $self->open_padlock_pixmap()  ;
    }
    
    return { -image => $pixmap } ;
}    

sub closed_padlock_pixmap {
    my( $self ) = @_;
    
    my( $pix );
    unless ($pix = $self->{'_closed_padlock_pixmap'}) {
    
        my $data = <<'END_OF_PIXMAP' ;
/* XPM */    
static char * padlock[] = {
"11 13 3 1",
"     c None",
".    c #FFFFFF",
"+    c #000000",
"           ",
"    +++    ",
"   +++++   ",
"  ++   ++  ",
"  +     +  ",
"  +     +  ",
" +++++++++ ",
" +++++++++ ",
" +++++++++ ",
" +++++++++ ",
" +++++++++ ",
"  +++++++  ",
"           "};
END_OF_PIXMAP
        
        $pix = $self->{'_closed_padlock_pixmap'} = $self->canvas->Pixmap( -data => $data );
    }
    return $pix;
}


### blank at the moment - perhaps put an "unlocked" icon in there later
### Need an image of some sort in place of the "locked" icon - for the refresh columns methods 
sub open_padlock_pixmap {
    my( $self ) = @_;
    
    my( $pix );
    unless ($pix = $self->{'_open_padlock_pixmap'}) {
    
        my $data = <<'END_OF_PIXMAP';
/* XPM */    
static char * padlock[] = {
"17 13 3 1",
"     c None",
".    c #FFFFFF",
"+    c #000000",
"           ",
"           ",
"           ",
"           ",                    
"           ",                    
"           ",                    
"           ",             
"           ",
"           ",     
"           ",     
"           ",     
"           ",
"           "};
END_OF_PIXMAP
        
        $pix = $self->{'_open_padlock_pixmap'} = $self->canvas->Pixmap( -data => $data );
    }
    return $pix;
}

# brings up a window for searching for loci / clones
sub slice_window{
    my ($self) = @_;
    
    my $slice_window = $self->{'_slice_window'};

    unless (defined ($slice_window) ){
        ## make a new window
        my $master = $self->canvas->toplevel;
        $slice_window = $master->Toplevel(-title => 'Open a slice');
        $slice_window->transient($master);
        
        $slice_window->protocol('WM_DELETE_WINDOW', sub{$slice_window->withdraw});
    
        my $label = $slice_window->Label(-text => qq`Enter chromosome coordinates for the start and end of the slice` .
                                                  qq` to open the clones contained.`
                                         )->pack(-side => 'top');

        my $cs_list = $self->SequenceSet->CloneSequence_list();
        my $entry_frame = $slice_window->Frame()->pack(-side => 'top', 
                                                       -padx =>  5,
                                                       -pady =>  5,
                                                       -fill => 'x'
                                                       );   
        my $slice_start   ||= $cs_list->[0]->chr_start || 0;
        $self->slice_min_ref(\$slice_start);
        my $min_label       = $entry_frame->Label(-text => "Slice:  start")->pack(-side   =>  'left');
        my $slice_min_entry = $entry_frame->Entry(-width        => 15,
                                                  -relief       => 'sunken',
                                                  -borderwidth  => 2,
                                                  -textvariable => $self->slice_min_ref,
                                                  #-font       =>   'Helvetica-14',   
                                                  )->pack(-side => 'left', 
                                                          -padx => 5,
                                                          -fill => 'x'
                                                           );
        my $slice_end   ||= $slice_start + 1e6;
        $self->slice_max_ref(\$slice_end);
        my $max_label       = $entry_frame->Label(-text => " end ")->pack(-side => 'left');
        my $slice_max_entry = $entry_frame->Entry(-width        => 15,
                                                  -relief       => 'sunken',
                                                  -borderwidth  => 2,
                                                  -textvariable => $self->slice_max_ref,
                                                  #-font       =>   'Helvetica-14',   
                                                  )->pack(-side => 'left', 
                                                          -padx => 5,
                                                          -fill => 'x',
                                                          );
        my $run_cancel_frame = $slice_window->Frame()->pack(-side => 'bottom', 
                                                               -padx =>  5,
                                                               -pady =>  5,
                                                               -fill => 'x'
                                                               );   
        my $run_button = $run_cancel_frame->Button(-text    => 'Run lace',
                                                   -command => sub{ 
                                                       $slice_window->withdraw;
                                                       $self->run_lace_on_slice;
                                                   }
                                                   )->pack(-side => 'left');
        
#        my $info = $run_cancel_frame->Label(-text => qq`The clones will not be truncated.`)->pack(-side => 'left',
#                                                                                                  -padx => 5,
#                                                                                                  -pady => 5,
#                                                                                                  -fill => 'x'
#                                                                                                  );
        my $cancel_button = $run_cancel_frame->Button(-text    => 'Cancel',
                                                      -command => sub { $slice_window->withdraw }
                                                      )->pack(-side => 'right');
        $self->{'_slice_window'} = $slice_window;
        $slice_window->bind('<Destroy>' , sub { $self = undef }  );
    }
    
    $slice_window->deiconify;
    $slice_window->raise;
    $slice_window->focus;
}
sub slice_min_ref{
    my ($self, $search) = @_;
    $self->{'_search_text'} = $search if $search;
    return $self->{'_search_text'};
}
sub slice_max_ref{
    my ($self, $context) = @_;
    $self->{'_context_size'} = $context if $context;
    return $self->{'_context_size'};    
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

