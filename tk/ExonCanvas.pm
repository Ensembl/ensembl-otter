
### ExonCanvas

package ExonCanvas;

use strict;
use Carp;
use CanvasWindow;
use Hum::Ace::SubSeq;
use vars ('@ISA');

@ISA = ('CanvasWindow');

sub new {
    my( $pkg, $tk ) = @_;
    
    my $button_frame = $tk->Frame;
    $button_frame->pack(
        -side   => 'top',
        -fill   => 'x',
        );
    my $self = $pkg->SUPER::new($tk);
    $self->button_frame($button_frame);
    
    return $self;
}

sub button_frame {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_button_frame'} = $bf;
    }
    return $self->{'_button_frame'};
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub subseq {
    my( $self ) = @_;
    
    my $name = $self->name
        or confess "name not set";
    return $self->xace_seq_chooser->get_SubSeq($name);
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
    
    my $expected_class = 'Hum::Ace::SubSeq';
    unless ($subseq->isa($expected_class)) {
        warn "Unexpected object '$subseq', expected a '$expected_class'";
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
    
    my $canvas = $self->canvas;
    my $empty  = $self->empty_string;
    my @pairs  = $self->position_pairs;
    for (my $n = 0; $n < @pairs; $n++) {
        foreach my $i (0,1) {
            my $num;
            if ($pos[$n]) {
                $num = $pos[$n][$i];
            }
            $num ||= $empty;
            my $obj = $pairs[$n][$i];
            $canvas->itemconfigure($obj, -text => $num);
        }
    }
    if (my $over = @pairs - @pos) {
        $self->trim_position_pairs($over);
        $self->fix_window_min_max_sizes;
    }
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


sub initialize {
    my( $self ) = @_;
    
    my $sub    = $self->subseq;
    my $canvas = $self->canvas;

    my $method = $sub->GeneMethod;
    $self->add_SubSeq_exons($sub);

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
    my $top = $canvas->toplevel;
    my $window_close = sub {
        my ($sub, $ace) = $self->to_ace_subseq;
        unless ($sub and $sub->is_archival) {
            require Tk::Dialog;
            my $name = $self->name;
            my $dialog = $self->canvas->toplevel->Dialog(
                -title  => 'Save changes?',
                -text   => "Save changes to SubSequence '$name' ?",
                -default_button => 'Yes',
                -buttons    => [qw{ Yes No Cancel }],
                );
            my $ans = $dialog->Show;
            if ($ans eq 'Cancel') {
                return;
            }
            elsif ($ans eq 'Yes') {
                return unless $sub;
                my $xr = $self->xace_seq_chooser->xace_remote;
                if ($xr) {
                    $xr->load_ace($ace);
                    $xr->save;
                    $sub->is_archival(1);
                } else {
                    $self->message("No xace attached");
                    return;
                }
            }
        }
        $self->delete_chooser_window_ref;
        # Have to specifically undef $self, or the
        # ExonCanvas object doesn't get destroyed,
        # because the other closures still reference it.
        $self = undef;
        $top->destroy;
    };
    
    ### Buttons

    my $bf = $self->button_frame;
   
    my $show_sub_button = $bf->Button(
        -text       => 'Show',
        -command    => sub{
                my $xr = $self->xace_seq_chooser->xace_remote;
                if ($xr) {
                    $xr->show_SubSeq($self->subseq);
                } else {
                    $self->message("No xace attached");
                }
            });
    $show_sub_button->pack(
        -side   => 'left',
        );
    
    if ($method->is_mutable) {

        # Sort the postions
        my $sort_button = $bf->Button(
            -text       => 'Sort',
            -command    => sub{ $self->sort_position_pairs },
                );
        $sort_button->pack(
            -side   => 'left',
            );
        
        # Merge overlapping positions
        my $merge_button = $bf->Button(
            -text       => 'Merge',
            -command    => sub{ $self->merge_position_pairs },
                );
        $merge_button->pack(
            -side   => 'left',
            );

        # Save in xace
        my $save_button = $bf->Button(
            -text       => 'Save',
            -command    => sub{
                my ($sub, $ace) = $self->to_ace_subseq;
                #warn $ace;
                my $xr = $self->xace_seq_chooser->xace_remote;
                if ($xr) {
                    $xr->load_ace($ace);
                    $xr->save;
                    $sub->is_archival(1);
                } else {
                    $self->message("No xace attached");
                }
            });
        $save_button->pack(
            -side   => 'left',
            );

        # Keyboard editing commands
        $canvas->Tk::bind('<Left>',      sub{ $self->canvas_text_go_left   });
        $canvas->Tk::bind('<Right>',     sub{ $self->canvas_text_go_right  });
        $canvas->Tk::bind('<Up>',        sub{ $self->increment_int    });
        $canvas->Tk::bind('<Down>',      sub{ $self->decrement_int    });
        $canvas->Tk::bind('<BackSpace>', sub{ $self->canvas_backspace });

        $canvas->Tk::bind('<<digit>>', [sub{ $self->canvas_insert_character(@_) }, Tk::Ev('A')]);
        $canvas->eventAdd('<<digit>>', map "<KeyPress-$_>", 0..9);

        # Control-Left for switching strand
        $canvas->Tk::bind('<Control-Button-1>', sub{
            $self->control_left_button_handler;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub )
            }
        });

        # For pasting in coords from clipboard
        $canvas->Tk::bind('<Button-2>', sub{
            $self->middle_button_paste;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub )
            }
        });
        
        # Focus on current text
        $canvas->Tk::bind('<Button-1>', sub{
            $self->left_button_handler;
            $self->focus_on_current_text;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub )
            }
        });
    } else {
        # SubSeq with an immutable method
        
        # Only select current text - no focus
        $canvas->Tk::bind('<Button-1>', sub{
            $self->left_button_handler;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub )
            }
        });
    }
    
    # To close window
    my $close_button = $bf->Button(
        -text       => 'Close',
        -command    => $window_close,
            );
    $close_button->pack(
        -side   => 'right',
        );
    
    ### Event bindings
    $canvas->Tk::bind('<Control-a>', $select_all_sub);
    $canvas->Tk::bind('<Control-A>', $select_all_sub);
    
    # For extending selection
    $canvas->Tk::bind('<Shift-Button-1>', sub{
        $self->shift_left_button_handler;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });
    
    # Trap window close
    $top->protocol('WM_DELETE_WINDOW', $window_close);
    $canvas->Tk::bind('<Control-q>',   $window_close);
    $canvas->Tk::bind('<Control-Q>',   $window_close);
    $canvas->Tk::bind('<Control-w>',   $window_close);
    $canvas->Tk::bind('<Control-W>',   $window_close);
    #$top->transient($top->parent);
    
    $self->fix_window_min_max_sizes;
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
    if (grep $_ eq 'exon_furniture', $canvas->gettags($obj)) {
        if (my $head_end = $canvas->itemcget($obj, 'arrow')) {
            my $new_end = ($head_end eq 'first') ? 'last' : 'first';
            $canvas->itemconfigure($obj, 
                -arrow   => $new_end,
                );
        }
    }
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
    my $strand = $self->subseq->strand;
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
        
    my $sub = $self->to_ace_subseq;
    my $text = $sub->as_ace_file_text;
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
    
    my @ints = $text =~ /(\d+)/g;
    
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
    
    my( $m );
    unless ($m = $self->{'_coord_matrix'}) {
        $m = [];
        my $uw      = $self->font_unit_width;
        my $size    = $self->font_size;
        my $max_chars = 8;  # For coordinates up to 99_999_999
        my $text_len = $max_chars * $uw;
        my $half = int($size / 2);
        my $pad  = int($size / 6);
        
        my $x1 = $half + $text_len;
        my $y1 = $half;
        push(@$m,
            $size, $half, $pad,
            $x1,               $y1,
            $x1 + ($size * 2), $y1 + $size,
            );
        $self->{'_coord_matrix'} = $m;
        
        # Create rectangle to pad canvas to max number width
        my $canvas = $self->canvas;
        $canvas->createRectangle(
            $half, $half,
            $half + (2 * ($text_len + $size)), $half + $size,
            -fill       => undef,
            -outline    => undef,
            -tags       => ['max_width_rectangle'],
            );
    }
    
    my $i = $self->next_position_pair_index;
    my( $size, $half, $pad, @bbox ) = @$m;
    my $y_offset = $i * ($size + (2 * $pad));
    $bbox[1] += $y_offset;
    $bbox[3] += $y_offset;
    return( $size, $half, $pad, @bbox );
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

sub to_ace_subseq {
    my( $self ) = @_;

    my @exons = $self->Exons_from_canvas or return;
    my $arch_str = $self->archive_string;
    my $subseq = $self->subseq;
    $subseq->replace_all_Exons(@exons);
    my $new_str = $subseq->as_ace_file_format_text;
    if ($new_str eq $arch_str) {
        $subseq->is_archival(1);
    } else {
        $subseq->is_archival(0);
    }
    return($subseq, $new_str);
}

sub archive_string {
    my( $self ) = @_;
    
    my( $arch );
    unless ($arch = $self->{'_archive_string'}) {
        my $subseq = $self->subseq;
        $arch = $subseq->as_ace_file_format_text;
        $self->{'_archive_string'} = $arch;
    }
    return $arch;
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

=head1 NAME - ExonCanvas

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

