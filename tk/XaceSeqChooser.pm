
### XaceSeqChooser

package XaceSeqChooser;

use strict;
use Carp;
use CanvasWindow;
use vars ('@ISA');
use Hum::Ace;

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
    $self->add_buttons;
    $self->bind_events;
    return $self;
}

sub button_frame {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_button_frame'} = $bf;
    }
    return $self->{'_button_frame'};
}

sub add_buttons {
    my( $self, $tk ) = @_;
    
    my $bf = $self->button_frame;
    my $x_attach = $bf->Button(
        -text       => 'attach xace',
        -command    => sub{
            $self->get_xace_window_id;
            });
    $x_attach->pack(
        -side   => 'left',
        );
   
    my $clone_sub = $bf->Button(
        -text       => 'show subseq',
        -state      => 'disabled',
        -command    => sub{
            $self->clone_sub_switch;
            });
    $clone_sub->pack(
        -side   => 'left',
        );
    $self->clone_sub_switch_button($clone_sub);
}

sub bind_events {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;

    $canvas->Tk::bind('<Button-1>', [
        sub{ $self->left_button_handler(@_); },
        Tk::Ev('x'), Tk::Ev('y') ]);
    $canvas->Tk::bind('<Shift-Button-1>', [
        sub{ $self->shift_left_button_handler(@_); },
        Tk::Ev('x'), Tk::Ev('y') ]);
}

sub left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;

    $self->deselect_all;
    if (my $obj = $canvas->find('withtag', 'current')) {
        $self->highlight($obj);
    }
    $self->update_clone_sub_switch_button;
}

sub shift_left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;

    if (my $obj = $canvas->find('withtag', 'current')) {
        if ($self->is_selected($obj)) {
            $self->remove_selected($obj);
        } else {
            $self->highlight($obj);
        }
    }
    $self->update_clone_sub_switch_button;
}

{
    my $sel_tag = 'SelectedThing';

    sub highlight {
        my( $self, @obj ) = @_;

        my $canvas = $self->canvas;
        foreach my $o (@obj) {
            my @bbox = $canvas->bbox($o);
            $bbox[0] -= 1;
            $bbox[1] -= 1;
            $bbox[2] += 1;
            $bbox[3] += 1;
            my $r = $canvas->createRectangle(
                @bbox,
                -outline    => undef,
                -fill       => '#ffd700',
                -tags       => [$sel_tag],
                );
            $canvas->lower($r, $o);
            $self->add_selected($o, $r);
        }
    }

    sub deselect_all {
        my( $self ) = @_;

        my $canvas = $self->canvas;
        $canvas->delete($sel_tag);
        $self->{'_selected_list'} = undef;
    }

    sub add_selected {
        my( $self, $obj, $rect ) = @_;

        $self->{'_selected_list'}{$obj} = $rect;
    }

    sub remove_selected {
        my( $self, @obj ) = @_;

        my $canvas = $self->canvas;
        foreach my $o (@obj) {
            if (my $d = $self->{'_selected_list'}{$o}) {
                $canvas->delete($d);
                delete($self->{'_selected_list'}{$o});
            }
        }
    }

    sub is_selected {
        my( $self, $obj ) = @_;

        return $self->{'_selected_list'}{$obj} ? 1 : 0;
    }

    sub list_selected {
        my( $self ) = @_;

        if (my $a = $self->{'_selected_list'}) {
            return sort {$a <=> $b} keys %$a;
        } else {
            return;
        }
    }
}

sub update_clone_sub_switch_button {
    my( $self ) = @_;
    
    my $button = $self->clone_sub_switch_button;
    if (my @selected = $self->list_selected) {
        $button->configure(
            -state  => 'normal',
            );
    } else {
        $button->configure(
            -state  => 'disabled',
            );
    }
}

sub clone_sub_switch_button {
    my( $self, $button ) = @_;
    
    if ($button) {
        $self->{'_clone_sub_switch_button'} = $button;
    }
    return $self->{'_clone_sub_switch_button'};
}

sub ace_handle {
    my( $self, $adbh ) = @_;
    
    if ($adbh) {
        $self->{'_ace_database_handle'} = $adbh;
    }
    return $self->{'_ace_database_handle'}
        || confess "ace_handle not set";
}

sub max_seq_list_length {
    return 100;
}

sub list_genome_sequences {
    my( $self, $offset ) = @_;
    
    $offset ||= 0;
    
    my $adbh = $self->ace_handle;
    my $max = $self->max_seq_list_length;
    my @gen_seq_list = map $_->name,
        $adbh->fetch(Genome_Sequence => '*');
    my $total = @gen_seq_list;
    my $end = $offset + $max - 1;
    $end = $total - 1 if $end > $total;
    my @slice = @gen_seq_list[$offset..$end];
    return($total, @slice);
}

sub sequence_list {
    my( $self, @sequences ) = @_;
    
    if (@sequences) {
        $self->{'_sequence_list'} = [@sequences];
    }
    if (my $slist = $self->{'_sequence_list'}) {
        return @$slist;
    } else {
        return;
    }
}

sub draw_clone_list {
    my( $self ) = @_;
    
    my @slist = $self->sequence_list;
    unless (@slist) {
        my( $offset );
        ($offset, @slist) = $self->list_genome_sequences;
        $self->sequence_list(@slist);
    }
    my $canvas = $self->canvas;
    my $font = $self->font;
    my $size = $self->font_size;
    my $pad  = int($size / 6);
    my $half = int($size / 2);

    
    my $tag = 'clone';
    my $x = 0;
    my $y = 0;
    for (my $i = 0; $i < @slist; $i++) {
        my $start_text = $canvas->createText(
            $x, $y,
            -anchor     => 'nw',
            -text       => $slist[$i],
            -font       => [$font, $size, 'bold'],
            -tags       => [$tag],
            );
        if (($i + 1) % 20) {
            $y += $size + $pad;
        } else {
            $y = 0;
            my $x_max = ($canvas->bbox($tag))[2];
            $x = $x_max + ($size * 2);
        }
    }
}

sub xace_window_id {
    my( $self, $xwid ) = @_;
    
    if ($xwid) {
        $self->{'_xace_window_id'} = $xwid;
    }
    unless ($xwid = $self->{'_xace_window_id'}) {
        my $xwid = $self->get_xace_window_id;
        $self->{'_xace_window_id'} = $xwid;
    }
    return $xwid;
}

sub get_xace_window_id {
    my( $self ) = @_;
    
    $self->message("Please click on the xace main window with the cross-hairs");
    local *XWID;
    open XWID, "xwininfo |"
        or confess "Can't open pipe from xwininfo : $!";
    my( $xwid );
    while (<XWID>) {
        # xwininfo: Window id: 0x7c00026 "ACEDB 4_9c, lace bA314N13"
        if (/Window id: (\w+) "([^"]+)/) {
            if ($2 =~ /^ACEDB/) {
                $xwid = $1;
            } else {
                $self->message("'$2' is not an xace main window");
            }
        }
    }
    close XWID or confess "Error running xwininfo : $!";
    return $xwid;
}

sub message {
    my( $self, @message ) = @_;
    
    print STDERR "\n", @message, "\n";
}

1;

__END__

=head1 NAME - XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

