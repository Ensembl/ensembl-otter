
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
    $self->add_buttons_and_event_bindings;
    
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
    
    my $name = $self->name;
    return $self->xace_seq_chooser->get_SubSeq($name);
}

sub xace_seq_chooser {
    my( $self, $chooser ) = @_;
    
    if ($chooser) {
        $self->{'_xace_seq_chooser'} = $chooser;
    }
    return $self->{'_xace_seq_chooser'};
}

sub add_ace_subseq {
    my( $self, $subseq, $x_offset ) = @_;
    
    $x_offset ||= 0;
    
    my $expected_class = 'Hum::Ace::SubSeq';
    unless ($subseq->isa($expected_class)) {
        warn "Unexpected object '$subseq', expected a '$expected_class'";
    }
    
    my $y_offset = $self->drawing_y_max;
    
    my $strand = $subseq->strand;
    foreach my $ex ($subseq->get_all_Exons) {
        $y_offset += $self->add_exon_holder($ex->start, $ex->end, $strand, $x_offset, $y_offset);
    }
}

sub drawing_y_max {
    my( $self ) = @_;
    
    # Get the offset underneath everthing else
    return ($self->canvas->bbox('all'))[3];
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
        my( $self, @pair ) = @_;

        unless (@pair == 2) {
            confess "Expecting 2 numbers, but got ", scalar(@pair);
        }
        $self->{$pp_field} ||= [];
        push(@{$self->{$pp_field}}, [@pair]);
    }
    
    sub all_postion_pair_text {
        my( $self ) = @_;
        
        my $canvas = $self->canvas;
        my $empty  = $self->empty_string;
        my( @pos );
        foreach my $pair ($self->position_pairs) {
            my $start = $canvas->itemcget($pair->[0], 'text');
            my $end   = $canvas->itemcget($pair->[1], 'text');
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
            $self->all_postion_pair_text;
        
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
    
    sub next_position_pair_index {
        my( $self ) = @_;
        
        if (my $pp = $self->{$pp_field}) {
            return scalar @$pp;
        } else {
            return 0;
        }
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

sub add_buttons_and_event_bindings {
    my( $self ) = @_;
    
    my $canvas          = $self->canvas;
    my $deselect_sub = sub{ $self->deselect_all };
    $canvas->SelectionHandle(
        sub { $self->export_highlighted_text_to_selection(@_); }
        );
    my $select_all_sub = sub{
        $self->select_all_exon_pos;
        $canvas->SelectionOwn( -command => $deselect_sub )
            if $self->list_selected;
        };

    my $top = $canvas->toplevel;
    my $window_close = sub {
        my $so = $canvas->SelectionOwner;
        $self->delete_chooser_window_ref;
        # Have to specifically undef $self, or the ExonCanvas object
        # doesn't get destroyed.  (Due to closures?)
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
                    $xr->show_sequence($self->name);
                } else {
                    $self->message("No xace attached");
                }
            });
    $show_sub_button->pack(
        -side   => 'left',
        );
    
    my $sort_button = $bf->Button(
        -text       => 'Sort',
        -command    => sub{ $self->sort_position_pairs },
            );
    $sort_button->pack(
        -side   => 'left',
        );
    
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
    
    $canvas->Tk::bind('<Control-v>', sub{ $self->message('verbose') });

    $canvas->Tk::bind('<Button-1>', sub{
        $self->left_button_handler;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });

    $canvas->Tk::bind('<Shift-Button-1>', sub{
        $self->shift_left_button_handler;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });

    $canvas->Tk::bind('<Control-Button-1>', sub{
        $self->control_left_button_handler;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });

    $canvas->Tk::bind('<Button-2>', sub{
        $self->middle_button_paste;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });

    $canvas->Tk::bind('<Left>',      sub{ $self->canvas_go_left   });
    $canvas->Tk::bind('<Right>',     sub{ $self->canvas_go_right  });
    $canvas->Tk::bind('<Up>',        sub{ $self->increment_int    });
    $canvas->Tk::bind('<Down>',      sub{ $self->decrement_int    });
    $canvas->Tk::bind('<BackSpace>', sub{ $self->canvas_backspace });
    
    $canvas->Tk::bind('<<digit>>', [sub{ $self->canvas_insert_character(@_) }, Tk::Ev('A')]);
    
    
    $canvas->eventAdd('<<digit>>', map "<KeyPress-$_>", 0..9);
    
    
    
    # Trap window close
    $top->protocol('WM_DELETE_WINDOW', $window_close);
    $canvas->Tk::bind('<Control-q>',   $window_close);
    $canvas->Tk::bind('<Control-Q>',   $window_close);
    $canvas->Tk::bind('<Control-w>',   $window_close);
    $canvas->Tk::bind('<Control-W>',   $window_close);
    #$top->transient($top->parent);
}

sub canvas_insert_character {
    my( $self, $canvas, $char ) = @_;
    
    my $text = $canvas->focus or return;
    $canvas->insert($text, 'insert', $char);
    $self->re_highlight($text);
}

sub canvas_go_left {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $text = $canvas->focus or return;
    my $pos = $canvas->index($text, 'insert');
    $canvas->icursor($text, $pos - 1);
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


sub canvas_go_right {
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
    $self->focus_on_current_text;
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
    my $text = $sub->as_ace_file_format_text;
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
    
    if (@ints == 1) {
        $self->deselect_all;
        my $obj  = $canvas->find('withtag', 'current')  or return;
        my $type = $canvas->type($obj)                  or return;
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
        my $max_chars = 8;  # For numbers up to 99_999_999
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
    my $y_offset = $i * ($size + $pad);
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
    
    $self->record_exon_inf($exon_id, $start_text, $strand_arrow, $end_text);
    $self->add_position_pair($start_text, $end_text);
    
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

sub record_exon_inf {
    my( $self, $exon_id, @inf ) = @_;
    
    $self->{'_exons'}{$exon_id} = [@inf];
}

sub to_ace_subseq {
    my( $self ) = @_;

    my $e = $self->{'_exons'};
    my $canvas = $self->canvas;
    
    my $subseq = Hum::Ace::SubSeq->new;
    $subseq->name($self->name);
    #$subseq->name($canvas->toplevel->cget('title'));

    my $subseq_strand = $self->subseq->strand;
    my $done_message = 0;
    foreach my $exid (keys %$e) {
        my ($start_id, $strand_arrow, $end_id) = @{$e->{$exid}};
                
        my $start  =  $canvas->itemcget($start_id, 'text');
        my $strand = ($canvas->itemcget($strand_arrow, 'arrow') eq 'last')
            ? 1 : -1;
        my $end    =  $canvas->itemcget(  $end_id, 'text');
        
        unless ($done_message) {
            $self->message("inconsistent strands")
                unless $strand == $subseq_strand;
            $done_message = 1;
        }
        
        my $exon = Hum::Ace::Exon->new;
        $exon->start($start);
        $exon->end($end);
        
        $subseq->add_Exon($exon);
    }
    $subseq->strand($subseq_strand);
    
    return $subseq;
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

