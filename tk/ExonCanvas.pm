
### ExonCanvas

package ExonCanvas;

use strict;
use Carp;
use CanvasWindow;
use Hum::Ace::SubSeq;
use vars ('@ISA');

@ISA = ('CanvasWindow');

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    $self->bind_events;
    
    return $self;
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

sub add_coordinate_pair {
    my( $self, $start, $end, $x_offset ) = @_;
    
    $x_offset ||= 0;
    
    my $y_offset = $self->drawing_y_max;
    my $strand = 1;
    if ($start and $end and $start > $end) {
        $strand = -1;
        ($start, $end) = ($end, $start);
    }
    $self->add_exon_holder($start, $end, $strand, $x_offset, $y_offset);
}

sub bind_events {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    $canvas->SelectionHandle(
        sub {
            $self->export_highlighted_text_to_selection(@_);
        });
    my $select_sub = sub{
        $self->select_all_exon_pos;
        $canvas->SelectionOwn(
            -command => sub{
                $self->deselect_all;
            },
            );
        };
    $canvas->Tk::bind('<Control-a>', $select_sub);
    $canvas->Tk::bind('<Control-A>', $select_sub);

    $canvas->Tk::bind('<Button-1>', [
        sub{ $self->left_button_handler(@_); },
        Tk::Ev('x'), Tk::Ev('y') ]);

    $canvas->Tk::bind('<Control-Button-1>', sub{
        $self->control_left_button_handler(@_);
        });

    $canvas->Tk::bind('<Button-2>', sub{
        $self->middle_button_paste;
        });
    
    my $top = $canvas->toplevel;
    $top->protocol('WM_DELETE_WINDOW', sub{
        $self->delete_chooser_window_ref;
        $self = undef;  # -- or the ExonCanvas object
                        #    doesn't get destroyed
        $top->destroy;
        });
    
    #$top->transient($top->parent);
}

sub delete_chooser_window_ref {
    my( $self ) = @_;
    
    my $name = $self->name;
    my $xc = $self->xace_seq_chooser;
    $xc->delete_subseq_edit_window($name);
}

sub left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;
    
    #warn "\n before: x=$x y=$y\n";
    #$x = $canvas->canvasx($x);
    #$y = $canvas->canvasy($y);
    #warn   "  after: x=$x y=$y\n";
    
    return if $self->delete_message;
    $self->deselect_all;
    
    my $obj  = $canvas->find('withtag', 'current')  or return;
    my $type = $canvas->type($obj)                  or return;
    my @tags = $canvas->gettags($obj);

    if ($type eq 'text') {

        # Position the icursor in the text
        #my $pos = $canvas->index($obj, [$x, $y]) + 1;
        #$canvas->icursor($obj, $pos);
        $canvas->icursor($obj, 'end');

        if ($canvas->itemcget($obj, 'text') eq $self->empty_string) {
            $canvas->itemconfigure($obj, 
                -text   => '',
                );
        }

        # Hightlight and focus if it isn't the
        # current object
        $canvas->focus($obj);
        $self->highlight($obj);
    }
    elsif (grep $_ eq 'exon_furniture', @tags) {
        my ($exon_id) = grep /^exon_id/, @tags;
        my( @exon_text );
        foreach my $ex_obj ($canvas->find('withtag', $exon_id)) {
            if ($canvas->type($ex_obj) eq 'text') {
                push(@exon_text, $ex_obj);
            }
        }
        $self->highlight(@exon_text);
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
    
    my $canvas = $self->canvas;
    my( @text );
    foreach my $obj ($self->list_selected) {
        if ($canvas->type($obj) eq 'text') {
            my $t = $canvas->itemcget($obj, 'text');
            push(@text, $t);
        }
    }
    my $strand = $self->subseq->strand;
    my $clip = '';
    for (my $i = 0; $i < @text; $i += 2) {
        my($start, $end) = @text[$i, $i + 1];
        $end ||= $self->empty_string;
        if ($strand == -1) {
            ($start, $end) = ($end, $start);
        }
        $clip .= "$start  $end\n";
    }
    
    if (length($clip) > $max_bytes)) {
        die "Text string longer than $max_bytes: ", length($clip);
    }
    return $clip;
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

sub add_exon_holder {
    my( $self, $start, $end, $strand, $x_offset, $y_offset ) = @_;
    
    $start ||= $self->empty_string;
    $end   ||= $self->empty_string;
    
    my $canvas  =          $self->canvas;
    my $font    =          $self->font;
    my $size    =          $self->font_size;
    my $exon_id = 'exon_id-'. $self->next_exon_number;
    my $pad  = int($size / 6);
    my $half = int($size / 2);
    my $arrow_size = $half - $pad;
    $y_offset += $half + $pad;
    
    my $line_length = $size;
    
    my $arrow = ($strand == 1) ? 'last' : 'first';
    
    my $start_text = $canvas->createText(
        $x_offset - $size, $y_offset,
        -anchor     => 'e',
        -text       => $start,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id],
        );
    
    my $strand_arrow = $canvas->createLine(
        $x_offset - $half, $y_offset,
        $x_offset + $half, $y_offset,
        -width      => 1,
        -arrow      => $arrow,
        -arrowshape => [$arrow_size, $arrow_size, $arrow_size - $pad],
        -tags       => [$exon_id, 'exon_furniture', 'exon_arrow'],
        );
    
    my $end_text = $canvas->createText(
        $x_offset + $size, $y_offset,
        -anchor     => 'w',
        -text       => $end,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id],
        );
    
    $self->record_exon_inf($exon_id, $start_text, $strand_arrow, $end_text);
    
    my $bkgd = $canvas->createRectangle(
        $canvas->bbox($exon_id),
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

