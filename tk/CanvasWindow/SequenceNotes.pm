
### CanvasWindow::SequenceNotes

package CanvasWindow::SequenceNotes;

use strict;
use Carp;
use base 'CanvasWindow';
use MenuCanvasWindow::XaceSeqChooser;
use CanvasWindow::SequenceNotes::History;

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
    my( $self ) = @_;
    
    my $ss = $self->SequenceSet;
    my $cs_list = $ss->CloneSequence_list;
    unless ($cs_list) {
        my $ds = $self->SequenceSetChooser->DataSet;
        $ds->fetch_all_CloneSequences_for_SequenceSet($ss);
        $ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
        $cs_list = $ss->CloneSequence_list;
    }
    return $cs_list;
}

### Might be able to make this a bit more general
sub refresh_column {
    my ($self, $col_no) = @_;

    my $col_tag = "col=$col_no";
    my $ss = $self->SequenceSet();
    my $ds = $self->SequenceSetChooser->DataSet();
    my $cs_list   = $self->get_CloneSequence_list;
    $ds->status_refresh_for_SequenceSet($ss);
    my $canvas = $self->canvas();
    
    for (my $i = 0; $i < @$cs_list; $i++) {
        my $cs = $cs_list->[$i];
        if (my ($status_text) = $canvas->find('withtag', "$col_tag&&cs=$i")) {
            my $new_text = _column_text_seq_note_status($cs);
	    delete $new_text->{'-tags'};    # Don't want to alter tags
	    $canvas->itemconfigure($status_text, %$new_text);
        } else {
            warn "No object withtag '$col_tag&&cs=$i'";
        }
    }
}

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
        my $norm = [$self->font, $self->font_size, 'normal'];
        my $bold = [$self->font, $self->font_size, 'bold'];
        $self->{'_column_methods'} = [
            \&_column_text_row_number,
            sub{
                # Use closure for font definition
                my $cs = shift;
                my $acc = $cs->accession;
                my $sv  = $cs->sv;
                return {-text => "$acc.$sv", -font => $bold, -tags => ['searchable']};
            },
            sub{
                # Use closure for font definition
                my $cs = shift;
                return {-text => $cs->clone_name, -font => $bold, -tags => ['searchable'] };
            },
	    \&_column_text_seq_note_status,
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
            },
            \&_column_text_seq_note_author,
            \&_column_text_seq_note_text,
            ];
    }
    return $self->{'_column_methods'};
}

sub _column_text_row_number {
    my( $cs, $row ) = @_;
    
    return { -text => 1 + $row };
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
        return { -text => $sn->text, -tags => ['searchable']};
    } else {
        return {};
    }
}

sub _column_text_seq_note_status{
    my $cs = shift;
    my $missing = join(", " => keys(%{$cs->unfinished()}));
    my $color   = 'darkgreen';
    if ($missing){
        warn $cs->accession . " is missing analyses:\t $missing\n";
	$missing = "missing";
	$color   = 'red';
    }else{
	$missing = "complete";
    }
    return {
        -text => $missing,
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

sub initialise {
    my( $self ) = @_;

    # Use a slightly smaller font so that more info fits on the screen
    $self->font_size(12);

    my $ss     = $self->SequenceSet or confess "No SequenceSet attached";
    my $write  = $ss->write_access;
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
    }

    ### Is hunting in CanvasWindow?
    my $hunter = sub{
	$top->Busy;
	$self->hunt_for_selection;
	$top->Unbusy;
    };
    
    ## First call to this returns empty list!
    #my @all_text_obj = $canvas->find('withtag', 'contig_text');
    
    $self->make_button($button_frame_2, 'Hunt selection', $hunter, 0);
    $top->bind('<Control-h>', $hunter);
    $top->bind('<Control-H>', $hunter);
    
    my $refesher = sub{
	$top->Busy;
	my $ds = $self->SequenceSetChooser->DataSet;
	my $ss = $self->SequenceSet;
	$ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
	$self->draw;
	$self->set_scroll_region_and_maxsize;
	$top->Unbusy;
    };
    $self->make_button($button_frame_2, 'Refresh', $refesher, 0);
    $top->bind('<Control-r>', $refesher);
    $top->bind('<Control-R>', $refesher);
    $top->bind('<F5>',        $refesher);
    
    my $refresh_status = sub {
	$top->Busy;
	$self->refresh_column(3);
	$top->Unbusy;
    };
    $self->make_button($button_frame_2, 'Refresh Ana. Status', $refresh_status, 8);
    $top->bind('<Control-a>', $refresh_status);
    $top->bind('<Control-A>', $refresh_status);
    $top->bind('<F6>',        $refresh_status);
    
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

    my @all_text_obj = $canvas->find('withtag', 'searchable');
    
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

sub set_seleted_from_canvas {
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





sub run_lace {
    my( $self ) = @_;
    
    ### Prevent opening of sequences already in lace sessions
    
    
    return unless $self->set_seleted_from_canvas;
    my $ss = $self->SequenceSet;
    my $cl = $self->Client;

    my $title = 'lace '. $self->name . $self->selected_sequence_string;
    
    ## For debugging to check selection OK:
    #foreach my $cs (@$selected) {
    #    printf "%s.%s\n", $cs->accession, $cs->sv;
    #}

    my $db = $self->Client->new_AceDatabase;
    $db->title($title);
    $db->error_flag(1);
    eval{
        $self->init_AceDatabase($db, $ss);
    };
    if ($@) {
        $db->error_flag(0);
        $self->exception_message($@, 'Error initialising database');
        ### This leaves clones locked if we have write_access
        return;
    }    

    my $xc = $self->make_XaceSeqChooser($title);
    ### Maybe: $xc->SequenceNotes($self);
    $xc->AceDatabase($db);
    my $write_flag = $cl->write_access ? $ss->write_access : 0;
    $xc->write_access($write_flag);  ### Can be part of interface in future
    $xc->Client($self->Client);
    $xc->initialize;
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
    $db->write_ensembl_data($ss);
    $db->write_pipeline_data($ss);
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

sub get_rows_list{
    my ($self) = @_;
    print STDERR "Fetching CloneSequence list...";
    return $self->get_CloneSequence_list;
}

sub draw {
    my( $self ) = @_;
    
    my $cs_list   = $self->get_rows_list;
    return unless scalar @$cs_list;
    print STDERR " done\n";
    my $size      = $self->font_size;
    my $canvas    = $self->canvas;
    my $methods   = $self->column_methods;
    my $max_width = $self->max_column_width;

    $canvas->delete('all');
    my $helv_def = ['Helvetica', $size, 'normal'];

#    my ($type) = $cs_list->[0] =~ /^(.+)=/;
#    print STDERR "Drawing $type list...";
    my $gaps = 0;
    my $gap_pos = {};
    for (my $i = 0; $i < @$cs_list; $i++) {
        my $row = $i + $gaps;
        my $cs = $cs_list->[$i];
        my $row_tag = "row=$row";
        my $y = $row * $size;

        unless ($i == 0) {
            my $last = $cs_list->[$i - 1];
            
            my $gap = 0; # default for non SequenceNotes methods inheriting this method
            if ($cs->can('chr_start')){
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

        for (my $col = 0; $col < @$methods; $col++) {
            my $x = $col * $size;
            my $col_tag = "col=$col";
            my $meth = $methods->[$col];
            
	    my $opt_hash = $meth->($cs, $i);
	    $opt_hash->{'-anchor'} ||= 'nw';
	    $opt_hash->{'-font'}   ||= $helv_def;
	    $opt_hash->{'-width'}  ||= $max_width;
	    $opt_hash->{'-tags'}   ||= [];
	    push(@{$opt_hash->{'-tags'}}, $row_tag, $col_tag, "cs=$i");
	    
#            my ($text, $font, $color, @tags) = $meth->($cs, $i);
            $canvas->createText(
                $x, $y,
		%$opt_hash
#                -anchor => 'nw',
#                -font   => $font || $helv_def,
#		-fill   => $color || 'black',
#                -width  => $max_width,
#                -tags   => [$row_tag, $col_tag, "cs=$i", @tags],
#                -text   => $text,
#			       
                );
        }
    }
    print STDERR " done\n";
    my $col_count = scalar @$methods;
    my $row_count = scalar @$cs_list + $gaps;
    
    print STDERR "Laying out table...";
    $self->layout_columns_and_rows($col_count, $row_count);
    print STDERR " done\n";
    print STDERR "Drawing background rectangles...";
    $self->draw_row_backgrounds($row_count, $gap_pos);
    print STDERR " done\n";
    $self->fix_window_min_max_sizes;
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

sub get_current_CloneSequence_index {
    my $self = shift @_ ;
    my $canvas = $self->canvas;
    my $obj = $canvas->find('withtag', 'current') or return;
     
    my ($i) = map /^cs=(\d+)/, $canvas->gettags($obj);  
#    warn "\n\n$i\n\n";
    return $i;

}

sub get_current_row_tag {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $obj = $canvas->find('withtag', 'current') or return;

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
    unless ($self->set_seleted_from_canvas) {
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
    $self->canvas->delete('msg');
    my $cs =  $self->get_CloneSequence_list->[$index];
    my $missing = join(", " => keys(%{$cs->unfinished()}));
    my $clone = $cs->accession . "." . $cs->sv;
    if($missing){
	$self->message("$clone is missing : $missing");
    }else{
	$self->message("$clone has a complete set of analyses");
    }
}
sub popup_ana_seq_history{
    my ($self) = @_;
    my $index = $self->get_current_CloneSequence_index ; 
    unless (defined $index ){
        return;
    }
    unless ( $self->check_for_History($index) ){
        # window has not been created already - create one
        my $cs =  $self->get_CloneSequence_list->[$index];
        my $clone_list = $cs->get_all_SequenceNotes;
        if (@$clone_list){
            my $top = $self->canvas->Toplevel();
            $top->transient($self->canvas->toplevel);
            my $hp  = CanvasWindow::SequenceNotes::History->new($top, 550 , 50);
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
1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

