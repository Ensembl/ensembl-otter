
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
    $self->current_state('clone');
    return $self;
}

sub button_frame {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_button_frame'} = $bf;
    }
    return $self->{'_button_frame'};
}

{
    my %state_label = (
        'clone'     => 'Show subseq',
        'subseq'    => 'Show clones',
        );

    sub current_state {
        my( $self, $state ) = @_;

        if ($state) {
            unless (my $label = $state_label{$state}) {
                confess "Not a permitted state '$state'";
            }
            $self->{'_current_state'} = $state;
            $self->update_clone_sub_switch_button;
        }
        return $self->{'_current_state'};
    }

    sub update_clone_sub_switch_button {
        my( $self ) = @_;

        my $state  = $self->current_state;
        my $button = $self->clone_sub_switch_button;
        if (my @selected = $self->list_selected or $state eq 'subseq') {
            $button->configure(
                -state  => 'normal',
                -text   => $state_label{$state},
                );
        } else {
            $button->configure(
                -state  => 'disabled',
                -text   => $state_label{$state},
                );
        }
    }
}

sub add_buttons {
    my( $self, $tk ) = @_;
    
    my $bf = $self->button_frame;
    my $x_attach = $bf->Button(
        -text       => 'Attach xace',
        -command    => sub{
            $self->get_xace_window_id;
            });
    $x_attach->pack(
        -side   => 'left',
        );
   
    my $clone_sub = $bf->Button(
        -text       => 'Show subseq',
        -state      => 'disabled',
        -command    => sub{
            $self->clone_sub_switch;
            });
    $clone_sub->pack(
        -side   => 'left',
        );
    $self->clone_sub_switch_button($clone_sub);
    
    my $quit_button = $bf->Button(
        -text       => 'Quit',
        -command    => sub{ exit 0; },
        );
    $quit_button->pack(
        -side   => 'right',
        );
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

    return if $self->delete_message;

    $self->deselect_all;
    if (my $obj = $canvas->find('withtag', 'current')) {
        $self->highlight($obj);
    }
    $self->update_clone_sub_switch_button;
}

sub shift_left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;

    return if $self->delete_message;

    if (my $obj = $canvas->find('withtag', 'current')) {
        if ($self->is_selected($obj)) {
            $self->remove_selected($obj);
        } else {
            $self->highlight($obj);
        }
    }
    $self->update_clone_sub_switch_button;
}

sub clone_sub_switch {
    my( $self ) = @_;
    
    if ($self->current_state eq 'clone') {
        $self->switch_to_subseq_display;   
    } else {
        $self->switch_to_clone_display;
    }
}

sub switch_to_subseq_display {
    my( $self ) = @_;
    
    my @clone_names = $self->list_selected_names;
    $self->deselect_all;
    $self->canvas->delete('all');
    $self->current_state('subseq');
    $self->draw_subseq_list(@clone_names);
}

sub switch_to_clone_display {
    my( $self ) = @_;
    
    my @subseq_names = $self->list_selected;
    $self->deselect_all;
    $self->canvas->delete('all');
    $self->current_state('clone');
    $self->draw_clone_list;
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
    return 1000;
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

sub clone_list {
    my( $self, @clones ) = @_;
    
    if (@clones) {
        $self->{'_clone_list'} = [@clones];
    }
    if (my $slist = $self->{'_clone_list'}) {
        return @$slist;
    } else {
        return;
    }
}

sub subseq_list {
    my( $self, @subseqs ) = @_;
    
    if (@subseqs) {
        $self->{'_subseq_list'} = [@subseqs];
    }
    if (my $slist = $self->{'_subseq_list'}) {
        return @$slist;
    } else {
        return;
    }
}

sub draw_clone_list {
    my( $self ) = @_;
    
    my @slist = $self->clone_list;
    unless (@slist) {
        my( $offset );  # To implement paging
        ($offset, @slist) = $self->list_genome_sequences;
        $self->clone_list(@slist);
    }
    
    $self->draw_sequence_list('clone', @slist);
}

sub draw_subseq_list {
    my( $self, @selected ) = @_;
    
    my( @subseq );
    foreach my $clone_name (@selected) {
        warn "Fetching sequence for '$clone_name'\n";
        my $clone = $self->get_CloneSeq($clone_name);
        foreach my $sub ($clone->get_all_SubSeqs) {
            push(@subseq, $sub->name);
        }
    }
    $self->draw_sequence_list('subseq', @subseq);
}

sub get_CloneSeq {
    my( $self, $clone_name ) = @_;
    
    my( $clone );
    unless ($clone = $self->{'_clone_sequences'}{$clone_name}) {
        $clone = $self->express_clone_and_subseq_fetch($clone_name);
        $self->{'_clone_sequences'}{$clone_name} = $clone;
    }
    return $clone;
}

sub express_clone_and_subseq_fetch {
    my( $self, $clone_name ) = @_;
    
    my $clone = Hum::Ace::CloneSeq->new;
    $clone->ace_name($clone_name);
    
    my $ace = $self->ace_handle;

    # These raw_queries are much faster than
    # fetching the whole Genome_Sequence object!
    $ace->raw_query("find Sequence $clone_name");
    my $sub_list = $ace->raw_query('show -a Subsequence');
    $sub_list =~ s/\0//g;   # Remove any nulls
    
    while ($sub_list =~ /^Subsequence\s+"([^"]+)"\s+(\d+)\s+(\d+)/mg) {
        my($name, $start, $end) = ($1, $2, $3);
        my $t_seq = $ace->fetch(Sequence => $name);
        my $sub = Hum::Ace::SubSeq
            ->new_from_name_start_end_transcript_seq(
                $name, $start, $end, $t_seq,
                );
        $clone->add_SubSeq($sub);
    }
    return $clone;
}

sub draw_sequence_list {
    my( $self, $tag, @slist ) = @_;

    my $canvas = $self->canvas;
    my $font = $self->font;
    my $size = $self->font_size;
    my $pad  = int($size / 6);
    my $half = int($size / 2);

    $canvas->delete('all');

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
    
    my $mid = $self->message("Please click on the xace main window with the cross-hairs");
    $self->delete_message($mid);
    local *XWID;
    open XWID, "xwininfo |"
        or confess "Can't open pipe from xwininfo : $!";
    my( $xwid );
    while (<XWID>) {
        # xwininfo: Window id: 0x7c00026 "ACEDB 4_9c, lace bA314N13"
        if (/Window id: (\w+) "([^"]+)/) {
            my $name = $2;
            if ($name =~ /^ACEDB/) {
                $xwid = $1;
                $self->message("Attached to:\n$name");
            } else {
                $self->message("'$name' is not an xace main window");
            }
        }
    }
    close XWID or confess "Error running xwininfo : $!";
    return $xwid;
}

sub list_selected_names {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my( @names );
    foreach my $obj ($self->list_selected) {
        my $n = $canvas->itemcget($obj, 'text');
        push(@names, $n);
    }
    return @names;
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

        if (my $sel = $self->{'_selected_list'}) {
            return sort {$a <=> $b} keys %$sel;
        } else {
            return;
        }
    }
}

1;

__END__

=head1 NAME - XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

