
### CanvasWindow::SequenceNotes

package CanvasWindow::SequenceNotes;

use strict;
use Carp;
use base 'CanvasWindow';
use MenuCanvasWindow::XaceSeqChooser;
use CanvasWindow::SequenceNotes::History;
use CanvasWindow::SequenceNotes::Status;
use TransientWindow::OpenRange;
use Evi::EviCollection;
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

        my $cl = $self->Client();
        my $ds = $self->SequenceSetChooser->DataSet;

        if ($cl->can('get_all_CloneSequences_for_DataSet_SequenceSet')) {
            $cl->get_all_CloneSequences_for_DataSet_SequenceSet($ds, $ss);
        } else {
            $cl->get_all_CloneSequences_for_SequenceSet($ss);
        }
        $cl->fetch_all_SequenceNotes_for_DataSet_SequenceSet($ds, $ss);
        $cl->status_refresh_for_DataSet_SequenceSet($ds, $ss);
        $cl->lock_refresh_for_DataSet_SequenceSet($ds, $ss); # do we need it?

        $cs_list = $ss->CloneSequence_list;
    }
    return $cs_list;
}

sub refresh_and_redraw {
    my $self = shift @_;
    my $top    = $self->canvas->toplevel;

	$top->Busy;

    $self->get_CloneSequence_list(1);
    $self->draw();

	$top->Unbusy;
}

# Not sure whether it should belong here or to SequenceSet.pm
#
sub find_CloneSequence_index_by_name {
    my ($self, $clone_name) = @_;

    my $ind = 0;
    for my $cs (@{$self->get_CloneSequence_list()}) {
        if($cs->accession().'.'.$cs->sv() eq $clone_name) {
            # print STDERR "find_CloneSequence_index_by_name: returning $ind for '$clone_name'\n";
            return $ind;
        }
        $ind++;
    }
    return undef;
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
    my $cl = $self->Client();
    my $ds = $self->SequenceSetChooser->DataSet();
    my $ss = $self->SequenceSet();
    if ($column_number == 3){
        # this is the ana_status column
        $cl->status_refresh_for_DataSet_SequenceSet($ds, $ss);
    }
    elsif($column_number == 7){
        # padlock column
        $cl->lock_refresh_for_DataSet_SequenceSet($ds, $ss);
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
        my $text_method  = \&_write_text ;   # this is the default method to be used  to display text (rather than drawing s graphic)
        my $image_method = \&_draw_image ;
        
        my $norm = [$self->font, $self->font_size, 'normal'];
        my $bold = [$self->font, $self->font_size, 'bold'];
        $self->{'_column_methods'} = [
            [$text_method, \&_column_text_row_number],
            [$text_method, 
                sub{
                    # Use closure for font definition
                    my $cs = shift;
                    my $acc_sv = $cs->accession .'.'. $cs->sv;
                    my $fontcolour = $cs->current_match()
                                    ? 'red'
                                    : $cs->is_match()
                                        ? 'darkred'
                                        : 'black';
                    return {-text => $acc_sv, -font => $bold, -fill => $fontcolour, -tags => ['searchable']};
                }],
            [$text_method, 
                sub{
                    # Use closure for font definition
                    my $cs = shift;
                    my $fontcolour = $cs->current_match()
                                    ? 'red'
                                    : $cs->is_match()
                                        ? 'darkred'
                                        : 'black';
                    return {-text => $cs->clone_name, -font => $bold, -fill => $fontcolour, -tags => ['searchable'] };
                }],
            [$text_method, \&_column_text_seq_note_status],
	        [$text_method , 
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
            [$text_method,  \&_column_text_seq_note_author],
            [$text_method,  \&_column_text_seq_note_text],
            [$image_method, \&_padlock_icon ]
            ];
    }
    return $self->{'_column_methods'};
}

sub _write_text{
    my ($canvas, @args) = @_ ;
    
    #warn "Drawing text with args [", join(', ', map "'$_'", @args), "]\n";
    
    $canvas->createText(@args) ;
}

sub _draw_image{
    my ($canvas, $x, $y, %args) = @_;
    
    ## need to remove some tags -as they are for create_text 
    delete $args{'-width'} ;
    delete $args{'-font'} ;
    delete $args{'-anchor'} ; 

    $canvas->createImage($x, $y, %args , -anchor => 'n');
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
        my $sn_text = $sn->text || '';
        return { -text => $prefix . $sn_text, -tags => ['searchable']};
    } else {
        return {};
    }
}


sub _column_text_seq_note_status {
    my $cs = shift;
    
    my $text  = 'unavailable';
    my $color = 'darkred';

    if (my $pipeStatus = $cs->pipelineStatus) {
        $text  = $pipeStatus->short_display;
        $color = $text eq 'completed' ? 'darkgreen' : 'red';
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
    
    # Don't need now that non-contiguous selections in
    # SequenceNotes don't open in multiple contigs
    #$canvas->CanvasBind('<Control-Button-1>', sub {
    #    return if $self->delete_message;
    #    $self->toggle_current;
    #    });

    my ( $comment, $comment_label );
    my ( $button_frame_1, $button_frame_2 );

    if ($write) {
	$button_frame_1 = $top->Frame->pack(-side => 'top');

	$button_frame_2 = $top->Frame->pack(-side => 'top');

	$comment_label = $button_frame_1->Label(-text => 'Note text:',);
	$comment_label->pack(-side => 'left',);
	my $comment_text = '';
        $self->set_note_ref(\$comment_text);
	$comment = $button_frame_1->Entry(-width        => 55,
                                          -textvariable => $self->set_note_ref(),
					  -font         => ['Helvetica', $self->font_size, 'normal'],
					  );
	$comment->pack(-side => 'left');
        my $clear_button = $button_frame_1->Button(-text    => 'clear'   ,
                                                   -command => sub { my $ref = $self->set_note_ref(); $$ref = undef; }
                                                   )->pack(-side => 'right');
	
	# Remove Control-H binding from Entry
	$comment->bind(ref($comment), '<Control-h>', '');
	$comment->bind(ref($comment), '<Control-H>', '');
	$button_frame_1->bind('<Destroy>', sub { $self = undef });

	my $set_reviewed = sub{
	    $self->save_sequence_notes($comment);
	};
	$self->make_button($button_frame_1, 'Set note', $set_reviewed, 0);
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
        # we want this to refresh all columns
        $self->_refresh_SequenceSet();
        #$self->_refresh_SequenceSet(3);
        #$self->refresh_column(3);
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
    if (Bio::Otter::Lace::Defaults::fetch_pipeline_switch()) {
        $canvas->Tk::bind('<Button-3>',  sub{ $self->popup_missing_analysis });
    }    
    
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
    my ($self, $start, $end) = @_;
    
    ### doing the same as set_selected_from_canvas
    ### but from the user input instead
    my $ss    = $self->SequenceSet;

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
            #warn "Comparing $cur_s to (<) $end and $cur_e to (>) $start, Found: $minOK, $maxOK, $both \n";
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

    my $db = $cl->new_AceDatabase;
    $db->error_flag(1);
    $db->title($title);
    $db->make_database_directory;

    my $write_access = $cl->write_access();

    if($write_access){
        # only lock the region if we have write access.
        eval{
            my $dsObj = $cl->get_DataSet_by_name($ss->dataset_name);
            confess "Can't find DataSet that SequenceSet belongs to"
                unless $dsObj;
            $dsObj->selected_SequenceSet($ss);
            my $ctg_list = $ss->selected_CloneSequences_as_contig_list()
                or confess "No CloneSequences selected";
            foreach my $ctg(@$ctg_list){
                my $lock_xml = $cl->lock_region_for_contig_from_Dataset($ctg, $dsObj);
                $db->write_lock_xml($lock_xml, $dsObj->name);
            }
        };
        
        if($@){ 
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
            }else{
                $self->exception_message($@, 'Error initialising database');
                print $@;
            }
            return;
        }
    }
    # now initialise the database
    eval{
        $db->init_AceDatabase($ss);
    };
    if ($@) {
        $db->error_flag(0);
        $self->exception_message($@, 'Error initialising database');
        return;
    }    

### Commented out for tropicalis cDNA annotation workshop
#    # Create EviCollection Object
#    my( $ec );
#    eval {
#        $ec = $self->make_EviCollection($ss);
#    };
#    if ($@) {
#        $db->error_flag(0);
#        $self->exception_message($@, 'Error creating EviCollection for supporting evidence selection');
#        return;
#    }

    warn "Making XaceSeqChooser";
    my $xc = $self->make_XaceSeqChooser($title);
    $xc->SequenceNotes($self) ;
    $xc->AceDatabase($db);
#    $xc->EviCollection($ec);
    my $write_flag = $cl->write_access ? $ss->write_access : 0;
    $xc->write_access($write_flag);  ### Can be part of interface in future
    $xc->initialize;
    $self->refresh_column(7) ; # 7 is the locks column
    
}

#sub make_EviCollection {
#    my( $self, $ss ) = @_;
#    
#    return unless Bio::Otter::Lace::Defaults::fetch_pipeline_switch();
#    my $dataset = $self->Client->get_DataSet_by_name($ss->dataset_name);
#    #$dataset->selected_SequenceSet($ss);
#    my $ctg = $ss->selected_CloneSequences;
#    my( $chr, $chr_start, $chr_end ) = $self->Client->chr_start_end_from_contig($ctg);
#    #print STDERR "EviSlice: $chr $chr_start-$chr_end\n";
#    
#    my $pipe_db = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($dataset->get_cached_DBAdaptor);
#    $pipe_db->assembly_type($ss->name);
#    my $slice_adaptor = $pipe_db->get_SliceAdaptor;
#    my $slice = $slice_adaptor->fetch_by_chr_start_end($chr, $chr_start, $chr_end);
#    warn "No components in tiling path in Slice for EviCollection"
#        unless @{$slice->get_tiling_path};
#
#    return Evi::EviCollection->new_from_pipeline_Slice(
#        $pipe_db,
#        $slice,
#        [qw{ vertrna Est2genome_human Est2genome_mouse Est2genome_other }],
#        #[qw{ vertrna }],
#        #[qw{ Uniprot }],
#        [],
#       );
#}

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

    my ($offset1, $offset2) = $self->_sanity_check($max_cs_list);
    warn "slice $offset1 .. $offset2\n";
    $cs_list = [ @{$cs_list}[$offset1..$offset2] ];

    return $cs_list;
}

sub _min {
    return ($_[0]<$_[1]) ? $_[0] : $_[1];
}

sub _max {
    return ($_[0]<$_[1]) ? $_[1] : $_[0];
}

sub _sanity_check{
    my ($self, $max) = @_;
    $max--;
    my $slice_a = $self->_user_first_clone_seq() - 1;
    my $slice_b = $self->_user_last_clone_seq()  - 1;
    my $max_pp  = $self->max_per_page();
    my $sanity_saved = 0;

    if($slice_a < 0){
        $sanity_saved = 1;
        $slice_a      = 0;
        $slice_b      = _min($max_pp-1, $max); # 'bumping' against the 5" boundary: show first page
    }
    if($slice_b > $max){
        $sanity_saved = 1;
        $slice_b      = $max;
        $slice_a      = _max(0, $max-$max_pp+1); # 'bumping' against the 3" boundary
    }

    if($slice_a > $slice_b){ # some unexpected error?
        $sanity_saved        = 1;
        ($slice_a, $slice_b) = (0, $max_pp-1); # show first page
    }

    $self->_user_first_clone_seq($slice_a + 1);
    $self->_user_last_clone_seq($slice_b + 1);    
    $self->max_per_page($slice_b - $slice_a + 1) unless $sanity_saved;
    
    return ($slice_a, $slice_b);
}
sub _user_first_clone_seq{
    my ($self, $min) = @_;
    if(defined($min) && $min=~/(-?\d+)/){
        $self->{'_user_min_element'} = $1;
    }
    return $self->{'_user_min_element'} || 0;
}
sub _user_last_clone_seq{
    my ($self, $max) = @_;
    if(defined($max) && $max=~/(-?\d+)/){
        $self->{'_user_max_element'} = $1;
    }
    return $self->{'_user_max_element'} || scalar(@{$self->get_CloneSequence_list});
}
sub max_per_page{
    my ($self, $max) = @_;
    $self->{'_max_per_page'} = $max if $max;
    return $self->{'_max_per_page'} || 35;
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
    
    my $prev_state   = ($cur_min > 1 ? 'normal' : 'disabled');
    my $next_state   = ($cur_max < $abs_max ? 'normal' : 'disabled');

    my $t = ceil( $abs_max / $ppg_max );
    # my $n = ceil( $cur_min / $ppg_max );
    my $n = int(10 * $cur_max / $ppg_max)/10; # leave only one digit after decimal point if at all

    return () if $prev_state eq 'disabled' && $next_state eq 'disabled';

    my $canvas   = $self->canvas();
    my $pg_frame = $canvas->Frame(-background => 'white');
    # fix a leak.....
    $pg_frame->bind('<Destroy>', sub {$self = undef});

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

sub draw_around_clone_name {
    my ($self, $clone_name, $pgsize) = @_;

    my $pghalfsize = $pgsize ? int($pgsize/2)+1 : 15;

    my $ind = $self->find_CloneSequence_index_by_name($clone_name);
    # print STDERR "draw_around_clone_name: ind=$ind\n";

    if(defined($ind)) {
        $self->_user_first_clone_seq($ind-$pghalfsize);
        $self->_user_last_clone_seq($ind+$pghalfsize);
        return $self->draw();
    } else {
        print STDERR "$clone_name not found in the SequenceSet '".
            $self->SequenceSet()->name()."!\n";
    }
}

sub draw_range{
    my ($self)   = @_;
    my $cs_list  = $self->get_CloneSequence_list;
    my $no_of_cs = scalar(@$cs_list);
    my $max_pp   = $self->max_per_page;

    unless($self->_allow_paging()){
        $self->_user_first_clone_seq(1);
        $self->_user_last_clone_seq($no_of_cs);
        return $self->draw();
    }

    my $trim_window = $self->{'_trim_window'}; 

    $self->_user_first_clone_seq(1);
    $self->_user_last_clone_seq($max_pp);

    unless ($trim_window){
        my $master = $self->canvas->toplevel;
        $master->withdraw(); # only do this first time
        $self->{'_trim_window'} = $trim_window = TransientWindow::OpenRange->new($master, 'Open Range');
        
        $trim_window->text_variable_ref('user_min', 1                  , 1);
        $trim_window->text_variable_ref('user_max', $max_pp            , 1);
        $trim_window->text_variable_ref('total'   , $no_of_cs          , 1);
        $trim_window->text_variable_ref('per_page', $max_pp            , 1);
        $trim_window->action('openRange', sub{ 
            my ($tw) = @_;
            $tw->hide_me;
            my $tl = $self->canvas->toplevel;
            $tl->deiconify; $tl->raise; $tl->focus;
            # need to copy input across.
            $self->_user_first_clone_seq(${$tw->text_variable_ref('user_min')});
            $self->_user_last_clone_seq (${$tw->text_variable_ref('user_max')});
            $self->draw() ;
        });
        $trim_window->action('openAll', sub { 
            my ($tw) = @_;
            $tw->hide_me;
            $self->_user_first_clone_seq(1);
            $self->_user_last_clone_seq(${$tw->text_variable_ref('total')});
            my $tl = $self->canvas->toplevel;
            $tl->deiconify; $tl->raise; $tl->focus;
            $self->draw();
        });
        $trim_window->initialise();
        $trim_window->draw();
    }
    $trim_window->show_me;

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
            my ($draw_method, $data_method) = @{$methods->[$col]};
            
	        my $opt_hash = $data_method->($cs, $i, $self) if $data_method;
            $opt_hash->{'-anchor'} ||= 'nw';
	        $opt_hash->{'-font'}   ||= $helv_def;
	        $opt_hash->{'-width'}  ||= $max_width;
	        $opt_hash->{'-tags'}   ||= [];
	        push(@{$opt_hash->{'-tags'}}, $row_tag, $col_tag, "cs=$i");
	    
            #warn "\ntags = [", join(', ', map "'$_'", @{$opt_hash->{'-tags'}}), "]\n";
            $draw_method->($canvas, $x, $y, %$opt_hash);  ## in most cases this will be $canvas->createText
        }
        
    }
    #print STDERR " done\n";
    my $col_count = scalar @$methods  + 1; # +1 fopr the padlock (non text column)
    my $row_count = scalar @$cs_list + $gaps;
    
    #print STDERR "Laying out table...";
    $self->layout_columns_and_rows($col_count, $row_count);
    #print STDERR " done\n";
    #print STDERR "Drawing background rectangles...";
    $self->draw_row_backgrounds($row_count, $gap_pos);
    #print STDERR " done\n";

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
    my( $self, $comment ) = @_;    # is $comment ever used???

    my $text = ${$self->set_note_ref()};
    $text =~ s/\s/ /g;
    $text =~ s/\s+$//;
    $text =~ s/^\s+//;
    unless ($self->set_selected_from_canvas) {
        $self->message("No clones selected");
        return;
    }
    my $cl = $self->Client();
    my $ds = $self->SequenceSetChooser->DataSet;

    my $new_note = Bio::Otter::Lace::SequenceNote->new;
    $new_note->author($cl->author); # will be ignored by the client anyway, but let it be known to the interface
    $new_note->text($text);
    $new_note->timestamp(time());
    my $seq_list = $self->SequenceSet->selected_CloneSequences;
    
    foreach my $cs (@$seq_list) {
        $cs->add_SequenceNote($new_note);    
        $cs->current_SequenceNote($new_note);

            # store new SequenceNote in the database
        $cl->push_sequence_note(
            $ds->name(),
            $cs->contig_name(),
            $new_note,
        );

            # sync state of SequenceNote objects with database
        for my $note (@{$cs->get_all_SequenceNotes()}) {
            $note->is_current(0);
        }
        $new_note->is_current(1);
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
        my $top = $self->canvas->Toplevel();
        $top->transient($self->canvas->toplevel);
        my $hp  = CanvasWindow::SequenceNotes::Status->new($top, 650 , 50);
	    # $hp->SequenceNotes($self); # can't have reference to self if we're inheriting
	    # clean up just won't work.
        $hp->SequenceSet($self->SequenceSet);
        $hp->SequenceSetChooser($self->SequenceSetChooser);
        $hp->name($cs->contig_name);
        $hp->initialise;
        $hp->clone_index($index);
        $hp->draw;
        $self->add_Status($hp);
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
            $hp->Client($self->Client());
	    # $hp->SequenceNotes($self); # can't have reference to self if we're inheriting
	    # clean up just won't work.
            $hp->SequenceSet($self->SequenceSet);
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
        use TransientWindow::OpenSlice;
        $self->{'_slice_window'} = 
            $slice_window = TransientWindow::OpenSlice->new($master, 'Open a slice');
        my $cs_list = $self->SequenceSet->CloneSequence_list();
        my $slice_start = $cs_list->[0]->chr_start       || 0;
        my $set_end     = $cs_list->[$#$cs_list]->chr_end || 0;
        $slice_window->text_variable_ref('slice_start', $slice_start, 1);
        $slice_window->text_variable_ref('set_end'    , $set_end    , 1);
        $slice_window->action('runLace', sub{
            my $sw = shift;
            $sw->hide_me;
            $self->run_lace_on_slice(${$sw->text_variable_ref('slice_start')}, ${$sw->text_variable_ref('slice_end')});
        });
        $slice_window->initialise();
        $slice_window->draw();
    }
    $slice_window->show_me();
}

sub set_note_ref{
    my ($self, $search) = @_;
    $self->{'_set_note'} = $search if $search;
    return $self->{'_set_note'};
}
1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

