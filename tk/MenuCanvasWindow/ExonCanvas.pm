
### MenuCanvasWindow::ExonCanvas

package MenuCanvasWindow::ExonCanvas;

use strict;
use Carp;
use Tk::Dialog;
use Hum::Ace::SubSeq;
use MenuCanvasWindow;
use vars ('@ISA');
use Hum::Ace;

@ISA = ('MenuCanvasWindow');

# "new" is in MenuCanvasWindow

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub SubSeq {
    my( $self, $sub ) = @_;
    
    if ($sub) {
        my $expected = 'Hum::Ace::SubSeq';
        unless ($sub->isa($expected)) {
            confess "Expected a '$expected', but got a '$sub'";
        }
        $self->{'_SubSeq'} = $sub;
        $self->canvas->toplevel->configure(-title => $sub->name);
    }
    return $self->{'_SubSeq'};
}

sub xace_seq_chooser {
    my( $self, $chooser ) = @_;
    
    if ($chooser) {
        $self->{'_xace_seq_chooser'} = $chooser;
    }
    return $self->{'_xace_seq_chooser'};
}

sub add_SubSeq_exons {
    my( $self, $subseq ) = @_;
    
    my $expected = 'Hum::Ace::SubSeq';
    unless ($subseq->isa($expected)) {
        warn "Unexpected object '$subseq', expected a '$expected'";
    }
    
    my $strand = $subseq->strand;
    foreach my $ex ($subseq->get_all_Exons) {
        $self->add_exon_holder($ex->start, $ex->end, $strand);
    }
}

{
    my $pp_field = '_position_pairs';

    sub position_pairs {
        my( $self, @pairs ) = @_;

        if (@pairs) {
            $self->{$pp_field} = [@pairs];
        }

        if (my $pp = $self->{$pp_field}) {
            return @$pp;
        } else {
            return;
        }
    }

    sub add_position_pair {
        my( $self, @pair_and_id ) = @_;

        unless (@pair_and_id == 3) {
            confess "Expecting 2 numbers and exon_id";
        }
        $self->{$pp_field} ||= [];
        push(@{$self->{$pp_field}}, [@pair_and_id]);
    }
    
    sub next_position_pair_index {
        my( $self ) = @_;
        
        if (my $pp = $self->{$pp_field}) {
            return scalar @$pp;
        } else {
            return 0;
        }
    }
    
    sub trim_position_pairs {
        my( $self, $length ) = @_;
        
        if (my $pp = $self->{$pp_field}) {
            my @del = splice(@$pp, -1 * $length, $length);
            if (@del != $length) {
                confess "only got ", scalar(@del), " elements, not '$length'";
            }
            my $canvas = $self->canvas;
            foreach my $exon_id (map $_->[2], @del) {
                $canvas->delete($exon_id);
            }
        } else {
            confess "No pairs to trim";
        }
    }
}

sub all_position_pair_text {
    my( $self ) = @_;

    my $canvas = $self->canvas;
    my $empty  = $self->empty_string;
    my( @pos );
    foreach my $pair ($self->position_pairs) {
        my $start = $canvas->itemcget($pair->[0], 'text');
        my $end   = $canvas->itemcget($pair->[1], 'text');
        foreach my $p ($start, $end) {
            $p = 0 if $p eq $empty;
        }
        if ($start < $end) {
            push(@pos, [$start, $end]);
        } else {
            push(@pos, [$end, $start]);
        }
    }
    return @pos;
}

sub set_position_pair_text {
    my( $self, $pp, $text_pair ) = @_;
    
    my $canvas = $self->canvas;
    foreach my $i (0,1) {
        my $obj = $pp->[$i];
        my $pos = $text_pair->[$i] || $self->empty_string;
        $canvas->itemconfigure($obj, -text => $pos);
    }
}

sub set_all_position_pair_text {
    my( $self, @coord ) = @_;

    my @pp_list = $self->position_pairs;
    if (@pp_list != @coord) {
        confess "position pair number '", scalar(@pp_list),
            "' doesn't match number of coordinates '", scalar(@coord), "'";
    }
    for (my $i = 0; $i < @pp_list; $i++) {
        $self->set_position_pair_text($pp_list[$i], $coord[$i]);
    }
}

sub sort_position_pairs {
    my( $self ) = @_;

    my %was_selected = map {$_, 1} $self->get_all_selected_text;
    $self->deselect_all;

    my $empty  = $self->empty_string;
    my $canvas = $self->canvas;

    my @sort = sort {$a->[0] <=> $b->[0] || $a->[1] <=> $b->[1]}
        $self->all_position_pair_text;

    my $n = 0;
    my( @select );
    foreach my $pp ($self->position_pairs) {
        foreach my $i (0,1) {
            my $pos = $sort[$n][$i] || $empty;
            my $obj = $pp->[$i];
            push(@select, $obj) if $was_selected{$pos};
            $canvas->itemconfigure($obj, -text => $pos);
        }
        $n++;
    }
    $self->highlight(@select) if @select;
}

sub merge_position_pairs {
    my( $self ) = @_;
    
    $self->sort_position_pairs;
    my @pos = $self->all_position_pair_text;
    my $i = 0;
    while (1) {
        my $this = $pos[$i];
        my $next = $pos[$i + 1] or last;
        if ($this->[0] <= $next->[1] and $this->[1] >= $next->[0]) {
            $this->[0] = ($this->[0] < $next->[0]) ? $this->[0] : $next->[0];
            $this->[1] = ($this->[1] > $next->[1]) ? $this->[1] : $next->[1];
            splice(@pos, $i + 1, 1);
        } else {
            $i++;
        }
    }
    
    my @pairs  = $self->position_pairs;
    for (my $i = 0; $i < @pos; $i++) {
        $self->set_position_pair_text($pairs[$i], $pos[$i]);
    }
    if (my $over = @pairs - @pos) {
        $self->trim_position_pairs($over);
        $self->fix_window_min_max_sizes;
    }
}

sub delete_selected_exons {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my @selected = $self->list_selected;
    $self->deselect_all;
    my( %del_exon );
    foreach my $obj (@selected) {
        my ($exon_id) = grep /^exon_id/, $canvas->gettags($obj);
        if ($exon_id) {
            $del_exon{$exon_id}++;
        }
    }
    
    my @text    = $self->all_position_pair_text;
    my @pp_list = $self->position_pairs;
    my $trim = 0;
    my( @keep );
    for (my $i = 0; $i < @pp_list; $i++) {
        my $exon_id = $pp_list[$i][2];
        my $count = $del_exon{$exon_id};
        if ($count and $count == 2) {
            $trim++;
        } else {
            push(@keep, $text[$i]);
        }
    }
    
    return unless $trim;
    
    $self->trim_position_pairs($trim);
    $self->set_all_position_pair_text(@keep);
}

sub add_coordinate_pair {
    my( $self, $start, $end ) = @_;
    
    my $strand = 1;
    if ($start and $end and $start > $end) {
        $strand = -1;
        ($start, $end) = ($end, $start);
    }
    $self->add_exon_holder($start, $end, $strand);
}

sub draw_subseq {
    my( $self ) = @_;
    
    $self->add_SubSeq_exons($self->SubSeq);
    $self->draw_translation_region;
}

sub initialize {
    my( $self ) = @_;
    
    my $sub    = $self->SubSeq;
    my $canvas = $self->canvas;
    my $top = $canvas->toplevel;

    $self->draw_subseq;

    # Routines to handle the clipboard
    my $deselect_sub = sub{ $self->deselect_all };
    $canvas->SelectionHandle(
        sub { $self->export_highlighted_text_to_selection(@_); }
        );
    my $select_all_sub = sub{
        $self->select_all_exon_pos;
        if ($self->list_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub );
        } else {
            warn "Nothing selected";
        }
    };

    # Save changes on window close
    my $window_close = sub {
        $self->window_close or return;
        
        #  Have to specifically undef $self here, or the    #
        #  MenuCanvasWindow::ExonCanvas object doesn't get  #
        #  destroyed, because the closures in this scope    #
        #  still reference it.                              #
        $self = undef;
        
        };

    my $menu_bar  = $self->menu_bar;
    my $file_menu = $self->make_menu('File');
    
    # Show the subsequence in fMap
    my $show_subseq = sub{ $self->show_subseq };
    $file_menu->add('command',
        -label          => 'Show SubSequence',
        -command        => $show_subseq,
        -accelerator    => 'Ctrl+H',
        -underline      => 1,
        );
    $canvas->Tk::bind('<Control-h>',   $show_subseq);
    $canvas->Tk::bind('<Control-H>',   $show_subseq);
    
    # Trap window close
    $top->protocol('WM_DELETE_WINDOW', $window_close);
    $canvas->Tk::bind('<Control-w>',   $window_close);
    $canvas->Tk::bind('<Control-W>',   $window_close);
    $canvas->Tk::bind('<Control-q>',   $window_close);
    $canvas->Tk::bind('<Control-Q>',   $window_close);

    my $edit_menu = $self->make_menu('Edit');
    
    # Select all positions
    $edit_menu->add('command',
        -label          => 'Select All',
        -command        => $select_all_sub,
        -accelerator    => 'Ctrl+A',
        -underline      => 7,
        );
    $canvas->Tk::bind('<Control-a>', $select_all_sub);
    $canvas->Tk::bind('<Control-A>', $select_all_sub);
    
    # Deselect all
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    if ($self->is_mutable) {

        # Save into db via xace
        my $save_command = sub{ $self->save_if_changed };
        $file_menu->add('command',
            -label          => 'Save',
            -command        => $save_command,
            -accelerator    => 'Ctrl+S',
            -underline      => 0,
            );
        $top->bind('<Control-s>',   $save_command);
        $top->bind('<Control-S>',   $save_command);
        $top->bind('<Return>',      $save_command);
        $top->bind('<KP_Enter>',    $save_command);
        
        # Add editing facilities for editable SubSeqs
        $edit_menu->add('separator');

        # Sort the positions
        my $sort_command = sub{ $self->sort_position_pairs };
        $edit_menu->add('command',
            -label          => 'Sort',
            -command        => $sort_command,
            -accelerator    => 'Ctrl+O',
            -underline      => 1,
            );
        $top->bind('<Control-o>',   $sort_command);
        $top->bind('<Control-O>',   $sort_command);
        
        # Merge overlapping exon coordinates
        $edit_menu->add('command',
            -label          => 'Merge',
            -command        => sub{ $self->merge_position_pairs },
            -accelerator    => 'Ctrl+M',
            -underline      => 0,
            );

        # Delete selected Exons
        my $delete_exons = sub{ $self->delete_selected_exons };
        $edit_menu->add('command',
            -label          => 'Delete',
            -command        => $delete_exons,
            -accelerator    => 'Ctrl+D',
            -underline      => 0,
            );
        $canvas->Tk::bind('<Control-d>', $delete_exons);
        $canvas->Tk::bind('<Control-D>', $delete_exons);

        # Choice of Method
        my @allowed_methods = map $_->name,
            $self->xace_seq_chooser->get_all_mutable_GeneMethods;
        my $current_method = $sub->GeneMethod->name;
        $self->method_name_var(\$current_method);

        my $method_menu = $self->make_menu('Method');
        foreach my $method_name (@allowed_methods ) {
            $method_menu->add('radiobutton',
                -label      => $method_name,
                -value      => $method_name,
                -variable   => \$current_method,
                );
        }


        # Keyboard editing commands
        $canvas->Tk::bind('<Left>',      sub{ $self->canvas_text_go_left   });
        $canvas->Tk::bind('<Right>',     sub{ $self->canvas_text_go_right  });
        $canvas->Tk::bind('<BackSpace>', sub{ $self->canvas_backspace      });
        
        # For entering digits into the text object which has keyboard focus
        $canvas->eventAdd('<<digit>>', map "<KeyPress-$_>", 0..9);
        $canvas->Tk::bind('<<digit>>', [sub{ $self->canvas_insert_character(@_) }, Tk::Ev('A')]);

        # Increases the number which has keyboard focus
        $canvas->eventAdd('<<increment>>', qw{ <Up> <plus> <KP_Add> <equal> });
        $canvas->Tk::bind('<<increment>>', sub{ $self->increment_int });

        # Decreases the number which has keyboard focus
        $canvas->eventAdd('<<decrement>>', qw{ <Down> <minus> <KP_Subtract> <underscore> });
        $canvas->Tk::bind('<<decrement>>', sub{ $self->decrement_int });

        # Control-Left mouse for switching strand
        $canvas->Tk::bind('<Control-Button-1>', sub{
            $self->control_left_button_handler;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });

        # Middle mouse pastes in coords from clipboard
        $canvas->Tk::bind('<Button-2>', sub{
            $self->middle_button_paste;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });
        
        # Handle left mouse
        $canvas->Tk::bind('<Button-1>', sub{
            $self->left_button_handler;
            $self->focus_on_current_text;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });
        
        # Widget for changing name
        $self->add_subseq_rename_widget;
    } else {
        # SubSeq with an immutable method
        
        # Only select current text - no focus
        $canvas->Tk::bind('<Button-1>', sub{
            $self->left_button_handler;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });
    }
    
    $file_menu->add('separator');
    
    # To close window
    $file_menu->add('command',
        -label          => 'Close',
        -command        => $window_close,
        -accelerator    => 'Ctrl-W',
        -underline      => 1,
        );
    
    
    # For extending selection
    $canvas->Tk::bind('<Shift-Button-1>', sub{
        $self->shift_left_button_handler;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });
    
    $self->fix_window_min_max_sizes;
}

sub is_mutable {
    my( $self ) = @_;
    
    return $self->SubSeq->GeneMethod->is_mutable;
}

sub window_close {
    my( $self ) = @_;
    
    my $xc = $self->xace_seq_chooser;
    if ($self->is_mutable and my $sub = $self->get_SubSeq_if_changed) {
        
        # Ask the user if changes should be saved
        my $name = $self->name;
        my $dialog = $self->canvas->toplevel->Dialog(
            -title          => 'Save changes?',
            -bitmap         => 'question',
            -text           => "Save changes to SubSequence '$name' ?",
            -default_button => 'Yes',
            -buttons        => [qw{ Yes No Cancel }],
            );
        my $ans = $dialog->Show;
        
        if ($ans eq 'Cancel') {
            return; # Abandon window close
        }
        elsif ($ans eq 'Yes') {
            $self->xace_save($sub) or return;
        }
    }
    $self->delete_chooser_window_ref;
    $self->canvas->toplevel->destroy;
    
    return 1;
}

sub show_subseq {
    my( $self ) = @_;

    my $xr = $self->xace_seq_chooser->xace_remote;
    if ($xr) {
        my $sub = $self->SubSeq;
        unless ($sub->is_archival) {
            $self->message("Not yet saved");
            return;
        }
        
        if ($sub->get_all_Exons) {
            $xr->show_SubSeq($sub);
        } else {
            $self->message("Can't show an empty SubSequence");
        }
    } else {
        $self->message("No xace attached");
    }
};


sub add_subseq_rename_widget {
    my( $self ) = @_;
    
    my $button_frame = $self->canvas->toplevel->Frame(
        -borderwidth    => 6,
        );
    $button_frame->pack(
        #-side => 'top',
        -anchor => 'nw',
        );
    
    my $sub_name_label = $button_frame->Label(
        -text   => "Name:",
        -anchor => 's',
        -padx   => 6,
        );
    $sub_name_label->pack(
        -side => 'left',
        );

    my $sub_name = $button_frame->Entry(
        -width              => 20,
        -exportselection    => 1,
        -relief             => 'flat',
        -background         => 'white',
        -selectbackground   => 'gold',
        -font               => [$self->font, $self->font_size, 'normal'],
        );
    $sub_name->pack(
        -side => 'left',
        );
    $sub_name->insert(0, $self->SubSeq->name);
    $self->subseq_name_Entry($sub_name);
}

sub subseq_name_Entry {
    my( $self, $entry ) = @_;
    
    if ($entry) {
        $self->{'_subseq_name_entry'} = $entry;
    }
    return $self->{'_subseq_name_entry'};
}

sub get_subseq_name {
    my( $self ) = @_;
    
    return $self->subseq_name_Entry->get;
}

sub set_subseq_name {
    my( $self, $new ) = @_;
    
    my $entry = $self->subseq_name_Entry;
    $entry->delete(0, 'end');
    $entry->insert(0, $new);
}

sub method_name_var {
    my( $self, $var_ref ) = @_;
    
    if ($var_ref) {
        $self->{'_method_name_var'} = $var_ref;
    }
    return $self->{'_method_name_var'};
}

sub get_GeneMethod_from_tk {
    my( $self ) = @_;
    
    my $meth_name = ${$self->method_name_var};
    return $self->xace_seq_chooser->get_GeneMethod($meth_name);
}

sub canvas_insert_character {
    my( $self, $canvas, $char ) = @_;
    
    my $text = $canvas->focus or return;
    $canvas->insert($text, 'insert', $char);
    $self->re_highlight($text);
}

sub increment_int {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $text = $canvas->focus or return;
    my $num = $canvas->itemcget($text, 'text');
    if ($num =~ /^\d+$/) {
        $num++;
        $canvas->itemconfigure($text, -text => $num);
        $self->re_highlight($text);
    }
}

sub decrement_int {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $text = $canvas->focus or return;
    my $num = $canvas->itemcget($text, 'text');
    if ($num =~ /^\d+$/) {
        $num--;
        $canvas->itemconfigure($text, -text => $num);
        $self->re_highlight($text);
    }
}

sub canvas_text_go_left {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $text = $canvas->focus or return;
    my $pos = $canvas->index($text, 'insert');
    $canvas->icursor($text, $pos - 1);
}

sub canvas_text_go_right {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $text = $canvas->focus or return;
    my $pos = $canvas->index($text, 'insert');
    $canvas->icursor($text, $pos + 1);
}

sub canvas_backspace {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $text = $canvas->focus or return;
    my $pos = $canvas->index($text, 'insert')
        or return;  # Don't delete when at beginning of string
    $canvas->dchars($text, $pos - 1);
    $self->re_highlight($text);
}

sub select_all_exon_pos {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    return $self->highlight($canvas->find('withtag', 'exon_pos'));
}

sub delete_chooser_window_ref {
    my( $self ) = @_;
    
    my $name = $self->name;
    my $xc = $self->xace_seq_chooser;
    $xc->delete_subseq_edit_window($name);
}

sub left_button_handler {
    my( $self ) = @_;
    
    return if $self->delete_message;
    $self->deselect_all;
    $self->shift_left_button_handler;
}

sub focus_on_current_text {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $obj  = $canvas->find('withtag', 'current')  or return;
    my $type = $canvas->type($obj)                  or return;
    if ($type eq 'text') {
        $canvas->focus($obj);

        # Position the icursor at the end of the text
        $canvas->icursor($obj, 'end');

        if ($canvas->itemcget($obj, 'text') eq $self->empty_string) {
            $canvas->itemconfigure($obj, 
                -text   => '',
                );
        }
        $canvas->focus($obj);
    }
}

sub shift_left_button_handler {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    $canvas->focus("");

    my $obj  = $canvas->find('withtag', 'current')  or return;
    my $type = $canvas->type($obj)                  or return;
    my @tags = $canvas->gettags($obj);

    if ($self->is_selected($obj)) {
        $self->remove_selected($obj);
    }
    elsif ($type eq 'text') {
        $self->highlight($obj);
    }
    elsif (grep $_ eq 'exon_furniture', @tags) {
        my ($exon_id) = grep /^exon_id/, @tags;
        my( @select, @deselect );
        foreach my $ex_obj ($canvas->find('withtag', $exon_id)) {
            if ($canvas->type($ex_obj) eq 'text') {
                if ($self->is_selected($ex_obj)) {
                    push(@deselect, $ex_obj);
                } else {
                    push(@select,   $ex_obj);
                }
            }
        }
        $self->remove_selected(@deselect) if @deselect;
        $self->highlight(@select)         if @select;
    }
}

sub control_left_button_handler {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $obj = $canvas->find('withtag', 'current')
        or return;
    return unless $canvas->type($obj) eq 'line';
    my $exon_arrow_tag = 'exon_arrow';
    if (grep $_ eq $exon_arrow_tag, $canvas->gettags($obj)) {
        if (my $head_end = $canvas->itemcget($obj, 'arrow')) {
            my $new_end = ($head_end eq 'first') ? 'last' : 'first';
            $canvas->itemconfigure($exon_arrow_tag, 
                -arrow   => $new_end,
                );
        }
    }
}

sub strand_from_tk {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my( $dir );
    foreach my $arrow ($canvas->find('withtag', 'exon_arrow')) {
        my $end = $canvas->itemcget($arrow, 'arrow');
        my $exon_dir = ($end eq 'first') ? 'reverse' : 'forward';
        if ($dir) {
            if ($exon_dir ne $dir) {
                $self->message("Inconsistent exon directions.  Guessing '$dir'");
                last;
            }
        } else {
            $dir = $exon_dir;
        }
    }
    
    return ($dir eq 'forward') ? 1 : -1;
}

sub empty_string {
    return '<empty>';
}

sub deselect_all {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    # Avoid unselectable empty text objects
    if (my $obj = $canvas->focus) {
        if ($canvas->type($obj) eq 'text') {
            my $text_string = $canvas->itemcget($obj, 'text');
            unless ($text_string) {
                $canvas->itemconfigure($obj, 
                    -text   => $self->empty_string,
                    );
            }
        }
    }
    $canvas->focus("");
    
    $self->SUPER::deselect_all;
}

sub export_highlighted_text_to_selection {
    my( $self, $offset, $max_bytes ) = @_;
    
    my @text = $self->get_all_selected_text;
    my $strand = $self->SubSeq->strand;
    my $clip = '';
    if (@text == 1) {
        $clip = $text[0];
    } else {
        for (my $i = 0; $i < @text; $i += 2) {
            my($start, $end) = @text[$i, $i + 1];
            $end ||= $self->empty_string;
            if ($strand == -1) {
                ($start, $end) = ($end, $start);
            }
            $clip .= "$start  $end\n";
        }
    }
    
    if (length($clip) > $max_bytes) {
        die "Text string longer than $max_bytes: ", length($clip);
    }
    return $clip;
}

sub get_all_selected_text {
    my( $self ) = @_;

    my $canvas = $self->canvas;
    my( @text );
    foreach my $obj ($self->list_selected) {
        if ($canvas->type($obj) eq 'text') {
            my $t = $canvas->itemcget($obj, 'text');
            push(@text, $t);
        }
    }
    return @text;
}

sub export_ace_subseq_to_selection {
    my( $self, $offset, $max_bytes ) = @_;
        
    my $sub = $self->new_SubSeq_from_tk;
    my $text = $sub->ace_string;
    if (length($text) > $max_bytes) {
        die "text too big";
    }
    warn $text;
    return $text;
}
    
sub middle_button_paste {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    my( $text );
    eval {
        $text = $canvas->SelectionGet;
    };
    return if $@;
    #warn "Trying to parse: [$text]\n";
    
    my( @ints );
    # match fMap "blue box" DNA selection
    if (@ints = $text =~ /Selection (\d+) ---> (\d+)/) {
        if ($ints[0] == $ints[1]) {
            # user clicked on single base pair
            @ints = ($ints[0]);
        }
    } else {
        # match general fMap "blue box" pattern
        unless (@ints = $text =~ /^\S+\s+-?(\d+)\s+-?(\d+)\s+\(\d+\)/) {
            # or just get all the integers
            @ints = grep ! /\./, $text =~ /([\.\d]+)/g;
        }
    }
    
    if (my $obj  = $canvas->find('withtag', 'current')) {
        $self->deselect_all;
        my $type = $canvas->type($obj) or return;
        if ($type eq 'text') {
            $canvas->itemconfigure($obj, 
                -text   => $ints[0],
                );
        }
        $self->highlight($obj);
    } else {
        for (my $i = 0; $i < @ints; $i += 2) {
            $self->add_coordinate_pair(@ints[$i, $i + 1]);
        }
        $self->fix_window_min_max_sizes;
    }
}

sub next_exon_holder_coords {
    my( $self ) = @_;
    
    my $i = $self->next_position_pair_index;
    my( $size, $half, $pad, $text_len, @bbox ) = $self->_coord_matrix;
    my $y_offset = $i * ($size + (2 * $pad));
    $bbox[1] += $y_offset;
    $bbox[3] += $y_offset;
    return( $size, $half, $pad, @bbox );
}

sub _coord_matrix {
    my( $self ) = @_;
    
    my( $m );
    unless ($m = $self->{'_coord_matrix'}) {
        my $uw      = $self->font_unit_width;
        my $size    = $self->font_size;
        my $max_chars = 8;  # For coordinates up to 99_999_999
        my $text_len = $max_chars * $uw;
        my $half = int($size / 2);
        my $pad  = int($size / 6);
        
        my $x1 = $half + $size + (2 * $text_len);
        my $y1 = $half;
        $m = [
            $size, $half, $pad, $text_len,
            $x1,               $y1,
            $x1 + ($size * 2), $y1 + $size,
            ];
        $self->{'_coord_matrix'} = $m;
        
        # Create rectangle to pad canvas to max number width
        my $canvas = $self->canvas;
        $canvas->createRectangle(
            $half, $half,
            $half + (4 * ($size + $text_len)), $half + $size,
            -fill       => undef,
            -outline    => undef,
            -tags       => ['max_width_rectangle'],
            );
    }
    return @$m;
}

sub add_exon_holder {
    my( $self, $start, $end, $strand ) = @_;
    
    $start ||= $self->empty_string;
    $end   ||= $self->empty_string;
    
    my $canvas  = $self->canvas;
    my $font    = $self->font;
    my $exon_id = 'exon_id-'. $self->next_exon_number;
    my( $size, $half, $pad,
        $x1, $y1, $x2, $y2 ) = $self->next_exon_holder_coords;
    my $arrow_size = $half - $pad;
    
    my $arrow = ($strand == 1) ? 'last' : 'first';
    
    my $start_text = $canvas->createText(
        $x1, $y1 + $half,
        -anchor     => 'e',
        -text       => $start,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id, 'exon_start', 'exon_pos'],
        );
    
    my $strand_arrow = $canvas->createLine(
        $x1 + $half, $y1 + $half,
        $x2 - $half, $y1 + $half,
        -width      => 1,
        -arrow      => $arrow,
        -arrowshape => [$arrow_size, $arrow_size, $arrow_size - $pad],
        -tags       => [$exon_id, 'exon_furniture', 'exon_arrow'],
        );
    
    my $end_text = $canvas->createText(
        $x2, $y1 + $half,
        -anchor     => 'w',
        -text       => $end,
        -font       => [$font, $size],
        -tags       => [$exon_id, 'normal', 'exon_end', 'exon_pos'],
        );
    
    $self->add_position_pair($start_text, $end_text, $exon_id);
    
    my $bkgd = $canvas->createRectangle(
        $x1, $y1, $x2, $y2,
        -fill       => 'white',
        -outline    => undef,
        -tags       => [$exon_id, 'exon_furniture'],
        );
    $canvas->lower($bkgd, $start_text);
    
    
    # Return how big we were
    return $size + $pad;
}

sub draw_translation_region {
    my( $self ) = @_;
    
    my( $size, $half, $pad, $text_len )
                    = $self->_coord_matrix;
    my $canvas      = $self->canvas;
    my $font        = $self->font;
    my $font_size   = $self->font_size;
    my @trans       = $self->SubSeq->translation_region;
    
    my $t1 = $canvas->createText(
        $half + $text_len, $size,
        -anchor => 'e',
        -text   => $trans[0],
        -font   => [$font, $size, 'bold'],
        -tags   => ['t_start', 'translation_region'],
        );
    my $t2 = $canvas->createText(
        (3 * $text_len) + (4 * $size), $size,
        -anchor => 'w',
        -text   => $trans[1],
        -font   => [$font, $size, 'bold'],
        -tags   => ['t_end', 'translation_region'],
        );
}

sub get_translation_region {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my( @region );
    foreach my $obj ($canvas->find('withtag', 'translation_region')) {
        push(@region, $canvas->itemcget($obj, 'text'));
    }
    return(@region);
}

sub get_SubSeq_if_changed {
    my( $self ) = @_;
    
    my $new = $self->new_SubSeq_from_tk;
    my $old = $self->SubSeq;
    if ($old->is_archival and $new->ace_string eq $old->ace_string) {
        return;
    } else {
        return $new;
    }
}

sub new_SubSeq_from_tk {
    my( $self ) = @_;

    my $sub = $self->SubSeq->clone;
    $sub->translation_region( $self->get_translation_region );
    $sub->name              ( $self->get_subseq_name        );
    $sub->replace_all_Exons ( $self->Exons_from_canvas      );
    $sub->GeneMethod        ( $self->get_GeneMethod_from_tk );
    $sub->strand            ( $self->strand_from_tk         );
    return $sub;
}

sub save_if_changed {
    my( $self ) = @_;
    
    if (my $sub = $self->get_SubSeq_if_changed) {
        $self->xace_save($sub);
    }
}

sub xace_save {
    my( $self, $sub ) = @_;
    
    confess "Missing SubSeq argument" unless $sub;
    
    my $ace = '';
    
    # Need to object if name has changed
    my $old = $self->SubSeq;
    my $old_name = $old->name;
    my $new_name = $sub->name;
    
    my $clone_name = $sub->clone_Sequence->name;
    if ($clone_name eq $new_name) {
        $self->message("Can't have SubSequence with same name as clone!");
        return;
    }
    
    # Do we need to rename?
    if ($old->is_archival and $new_name ne $old_name) {
        $ace .= qq{\n-R Sequence "$old_name" "$new_name"\n};
    }
    
    $ace .= $sub->ace_string;
    
    my $xc = $self->xace_seq_chooser;
    my $xr = $xc->xace_remote;
    if ($xr) {
        $xr->load_ace($ace);
        $xr->save;
        $xc->replace_SubSeq($sub, $old_name);
        $self->SubSeq($sub);
        $self->name($new_name);
        $sub->is_archival(1);
        return 1;
    } else {
        $self->message("No xace attached");
        return 0;
    }
}

sub Exons_from_canvas {
    my( $self ) = @_;
    
    my $done_message = 0;
    my( @exons );
    foreach my $pp ($self->all_position_pair_text) {
        if (grep $_ == 0, @$pp)  {
            $self->message("Error: Empty coordinate");
            return;
        }
        my $ex = Hum::Ace::Exon->new;
        $ex->start($pp->[0]);
        $ex->end  ($pp->[1]);
        push(@exons, $ex);
    }
    
    for (my $i = 0; $i < @exons; $i++) {
        my $this = $exons[$i];
        my $next = $exons[$i + 1] or last;
        if ($this->start <= $next->end and $this->end >= $next->start) {
            $self->message("Error: overlapping coordinates");
            return;
        }
    }
    
    return @exons;
}

sub max_exon_number {
    my( $self ) = @_;
    
    return $self->{'_max_exon_number'} || 0;
}

sub next_exon_number {
    my( $self ) = @_;
    
    $self->{'_max_exon_number'}++;
    return $self->{'_max_exon_number'};
}

sub DESTROY {
    my( $self ) = @_;
    
    my $name = $self->name;
    warn "Destroying: '$name'\n";
}

1;

__END__

=head1 NAME - MenuCanvasWindow::ExonCanvas

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

