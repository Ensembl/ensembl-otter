
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
    
    $self->bind_edit_commands;
    
    return $self;
}

sub add_ace_subseq {
    my( $self, $subseq, $x_offset ) = @_;
    
    $x_offset ||= 0;
    
    my $expected_class = 'Hum::Ace::SubSeq';
    unless ($subseq->isa($expected_class)) {
        warn "Unexpected object '$subseq', expected a '$expected_class'";
    }
    
    # Get the offset underneath everthing else
    my $y_offset = ($self->canvas->bbox('all'))[3];
    
    my $strand = $subseq->strand;
    foreach my $ex ($subseq->get_all_Exons) {
        $y_offset += $self->add_exon_holder($ex->start, $ex->end, $strand, $x_offset, $y_offset);
    }
}

sub add_coordinate_pair {
    my( $self, $start, $end, $x_offset ) = @_;
    
    $x_offset ||= 0;
    
    # Get the offset underneath everthing else
    my $y_offset = ($self->canvas->bbox('all'))[3];
    
    
}

sub bind_edit_commands {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    $canvas->SelectionHandle(
        sub {
            $self->export_ace_subseq_to_selection(@_);
        });
    my $select_sub = sub{
        #warn "becoming selection owner\n";
        $canvas->SelectionOwn(
            -command => sub{ warn "No longer selection owner" },
            );
        };
    $canvas->Tk::bind('<Control-c>', $select_sub);
    $canvas->Tk::bind('<Control-C>', $select_sub);

    $canvas->Tk::bind('<Button-1>', [
        sub{ $self->left_button_handle(@_); },
        Tk::Ev('x'), Tk::Ev('y') ]);
    $canvas->Tk::bind('<Button-2>', sub{
        $self->middle_button_paste;
        });

}

sub left_button_handle {
    my( $self, $canvas, $x, $y ) = @_;
    
    #warn "\n before: x=$x y=$y\n";
    #$x = $canvas->canvasx($x);
    #$y = $canvas->canvasy($y);
    #warn   "  after: x=$x y=$y\n";
    
    my $obj = $canvas->find('withtag', 'current');
    unless ($obj) {
        $self->canvas_deselect;
        return;
    }

    my $selected = $self->selected_obj;
    if ($obj != $selected) {
        $self->canvas_deselect;
    }

    my $type = $canvas->type($obj)
        or return;

    if ($type eq 'text') {

        # Position the icursor in the text
        my $pos = $canvas->index($obj, [$x, $y]) + 1;
        $canvas->icursor($obj, $pos);

        if ($canvas->itemcget($obj, 'text') eq $self->empty_string) {
            $canvas->itemconfigure($obj, 
                -text   => '',
                );
        }

        # Hightlight and focus if it isn't the
        # current object
        if ($obj != $selected) {
            $canvas->focus($obj);
            $self->maintain_highlight_rectangle($obj);
            $selected = $obj;
        }
    }
}

sub maintain_highlight_rectangle {
    my( $self, $obj ) = @_;
    
    my $canvas      = $self->canvas;
    my $sel_tag     = $self->selected_tag;
    $canvas->delete($sel_tag);

    my @bbox = $canvas->bbox($obj);
    $bbox[0] -= 1;
    $bbox[1] -= 1;
    $bbox[2] += 1;
    $bbox[3] += 1;
    my $rec = $canvas->createRectangle(
        @bbox,
        -fill       => '#ffff00',
        -outline    => undef,
        -tags       => [$sel_tag],
        );
    $canvas->lower($rec, $obj);
}

sub canvas_deselect {
    my( $self ) = @_;

    my $canvas = $self->canvas;
    $canvas->selectClear;

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

    $canvas->delete($self->selected_tag);
    $canvas->focus("");
    $self->selected_obj(0);
}

sub selected_obj {
    my( $self, $i ) = @_;
    
    if (defined $i) {
        $self->{'_selected_obj_index'} = $i;
    }
    return $self->{'_selected_obj_index'} || 0;
}

sub selected_tag {
    return 'SelectedThing';
}

sub empty_string {
    return '<empty>';
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
        $self->canvas_deselect;
        my $obj  = $canvas->find('withtag', 'current')  or return;
        my $type = $canvas->type($obj)                  or return;
        if ($type eq 'text') {
            $canvas->itemconfigure($obj, 
                -text   => $ints[0],
                );
        }
        $self->maintain_highlight_rectangle($obj);
    } else {
        warn "mulitple integers: @ints\n";
    }
}

sub add_exon_holder {
    my( $self, $start, $end, $strand, $x_offset, $y_offset ) = @_;
    
    my $canvas  =          $self->canvas;
    my $font    =          $self->font;
    my $size    =          $self->font_size;
    my $exon_id = 'exon-'. $self->next_exon_number;
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
        -tags       => [$exon_id],
        );
    
    my $end_text = $canvas->createText(
        $x_offset + $size, $y_offset,
        -anchor     => 'w',
        -text       => $end,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id],
        );
    
    $self->record_exon_inf($exon_id, $start_text, $strand_arrow, $end_text);
    
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
    $subseq->name($canvas->toplevel->cget('title'));

    my( $subseq_strand );
    foreach my $exid (keys %$e) {
        my ($start_id, $strand_arrow, $end_id) = @{$e->{$exid}};
                
        my $start  =  $canvas->itemcget($start_id, 'text');
        my $strand = ($canvas->itemcget($strand_arrow, 'arrow') eq 'last') ? 1 : -1;
        my $end    =  $canvas->itemcget(  $end_id, 'text');
        
        if ($subseq_strand) {
            $self->message("inconsistent strands")
                unless $strand == $subseq_strand;
        } else {
            $subseq_strand = $strand;
        }
        
        my $exon = Hum::Ace::Exon->new;
        $exon->start($start);
        $exon->end($end);
        
        $subseq->add_Exon($exon);
    }
    $subseq->strand($subseq_strand);
    
    return $subseq;
}

sub message {
    my( $self, @message ) = @_;
    
    # put in stuff to put message in window
    print STDERR "\n", @message, "\n";
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

sub font {
    my( $self, $font ) = @_;
    
    if ($font) {
        $self->{'_font'} = $font;
    }
    return $self->{'_font'} || 'lucidatypewriter';
}

sub font_size {
    my( $self, $font_size ) = @_;
    
    if ($font_size) {
        $self->{'_font_size'} = $font_size;
    }
    return $self->{'_font_size'} || 15;
}

1;

__END__

=head1 NAME - ExonCanvas

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

