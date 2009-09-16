
### CanvasWindow::EvidencePaster

package CanvasWindow::EvidencePaster;

use strict;
use Scalar::Util 'weaken';
use Hum::Ace::AceText;
use Hum::Sort 'ace_sort';
use Hum::ClipboardUtils 'evidence_type_and_name_from_text';
use base 'CanvasWindow';

sub initialise {
    my( $self, $evidence_hash ) = @_;

    my $canvas = $self->canvas;
    my $top = $canvas->toplevel;
    $top->configure(-title => "Supporting evidence");

    my $button_frame = $top->Frame->pack(
        -side => 'top',
        -fill => 'x',
        );

    my $draw = sub{ $self->draw_evidence };
    $top->bind('<Control-u>', $draw);
    $top->bind('<Control-u>', $draw);
    #$button_frame->Button(
    #    -text => 'Update',
    #    -command => $draw,
    #    )->pack(-side => 'left');

    my $paste = sub{ $self->paste_type_and_name };
    $top->bind('<Control-v>', $paste);
    $top->bind('<Control-V>', $paste);
    $top->bind('<Button-2>',  $paste);
    $button_frame->Button(
        -text => 'Paste',
        -command => $paste,
        )->pack(-side => 'left');

    my $delete = sub{ $self->remove_selected_from_evidence_list };
    $top->bind('<BackSpace>', $delete);
    $top->bind('<Delete>',    $delete);
    $top->bind('<Control-x>', $delete);
    $top->bind('<Control-X>', $delete);
    $button_frame->Button(
        -text => 'Delete',
        -command => $delete,
        )->pack(-side => 'left');

    my $close_window = sub{ $top->withdraw; };
    $top->bind('<Control-w>',           $close_window);
    $top->bind('<Control-W>',           $close_window);
    $top->protocol('WM_DELETE_WINDOW',  $close_window);
    $button_frame->Button(
        -text => 'Close',
        -command => $close_window,
        )->pack(-side => 'right');

    my $select_all = sub{ $self->select_all };
    $top->bind('<Control-a>', $select_all);
    $top->bind('<Control-A>', $select_all);
    $canvas->SelectionHandle( sub{ $self->selected_text_to_clipboard(@_) });

    $canvas->Tk::bind('<Button-1>',         sub{ $self->left_button_handler });
    $canvas->Tk::bind('<Control-Button-1>', sub{ $self->control_left_button_handler });
    $canvas->Tk::bind('<Shift-Button-1>',   sub{ $self->shift_left_button_handler });

    $canvas->Tk::bind('<Destroy>', sub{ $self = undef });


    $self->evidence_hash($evidence_hash);
    $self->draw_evidence;
}

sub ExonCanvas {
    my( $self, $ExonCanvas ) = @_;

    if ($ExonCanvas) {
        $self->{'_ExonCanvas'} = $ExonCanvas;
        weaken($self->{'_ExonCanvas'});
    }
    return $self->{'_ExonCanvas'};
}

sub left_button_handler {
    my( $self ) = @_;

    return if $self->delete_message;
    $self->deselect_all;
    $self->control_left_button_handler;
}

sub control_left_button_handler {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    my ($obj)  = $canvas->find('withtag', 'current&&!IGNORE')
      or return;

    if ($self->is_selected($obj)) {
        $self->remove_selected($obj);
    } else {
        $self->highlight($obj);
    }
}

sub shift_left_button_handler {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    return unless $canvas->find('withtag', 'current&&!IGNORE');

    $self->extend_highlight('!IGNORE');
}

sub select_all {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    $self->highlight(
        $canvas->find('withtag', '!IGNORE')
        );
}

sub evidence_hash {
    my( $self, $evidence_hash ) = @_;

    if ($evidence_hash) {
        $self->{'_evidence_hash'} = $evidence_hash;
    }
    return $self->{'_evidence_hash'};
}

sub remove_selected_from_evidence_list {
    my( $self ) = @_;

    my $canvas = $self->canvas;
    my $evi    = $self->evidence_hash;
    foreach my $obj ($self->list_selected) {
        my ($type) = $canvas->gettags($obj);
        my ($name) = $canvas->itemcget($obj, 'text');
        my $name_list = $evi->{$type} or die "No list with key '$type' in evidence hash";
        for (my $i = 0; $i < @$name_list; $i++) {
            if ($name_list->[$i] eq $name) {
                splice(@$name_list, $i, 1);
                #warn "Found '$name'!";
                last;
            }
        }
    }
    $self->draw_evidence;
}

sub draw_evidence {
    my( $self ) = @_;

    $self->deselect_all;

    my $evidence_hash = $self->evidence_hash;
    my $canvas = $self->canvas;
    $canvas->delete('all');

    my $norm = $self->font_fixed;
    my $bold = $self->font_fixed_bold;
    my $size = $self->font_size;
    my $row_height = $size + int($size / 6);
    my $type_pad = $row_height / 2;
    my $x = $size;

    my $y = 0;
    foreach my $type (qw{ Protein ncRNA cDNA EST }) {
        my $name_list = $evidence_hash->{$type} or next;
        next unless @$name_list;

        $canvas->createText(0, $y,
            -anchor => 'ne',
            -text   => $type,
            -font   => $bold,
            -tags   => ['IGNORE'],
            );

        my $x = $size;
        foreach my $text (@$name_list) {
            $canvas->createText($x, $y,
                -anchor => 'nw',
                -text   => $text,
                -font   => $norm,
                -tags   => [$type],
                );
            $y += $row_height;
        }

        $y += $type_pad
    }

    $self->canvas->toplevel->configure(
        -title => 'Evi: ' . $self->ExonCanvas->SubSeq->name,
        );
    $self->fix_window_min_max_sizes;
}

sub paste_type_and_name {
    my( $self ) = @_;

    if (my $clip = $self->get_clipboard_text) {
        $self->add_evidence_from_text($clip);
    }
}

sub add_evidence_from_text {
    my ($self, $text) = @_;

    my $ace = $self->ExonCanvas->XaceSeqChooser->ace_handle;

    if (my $clip_evi = evidence_type_and_name_from_text($ace, $text)) {
        $self->add_evidence_type_name_hash($clip_evi);
    }
}

sub add_evidence_type_name_hash {
    my ($self, $clip_evi) = @_;

    foreach my $type (keys %$clip_evi) {
        my $clip_list = $clip_evi->{$type};
        my $evi = $self->evidence_hash;
        my $list = $evi->{$type} ||= [];

        # Hmm, perhaps evidence hash should be two level hash?
        my %uniq = map {$_, 1} (@$list, @$clip_list);
        @$list = sort {ace_sort($a, $b)} keys %uniq;
    }
    $self->draw_evidence;
    foreach my $type (keys %$clip_evi) {
        my $clip_list = $clip_evi->{$type};
        foreach my $name (@$clip_list) {
            $self->highlight_evidence_by_type_name($type, $name);
        }
    }
}

sub highlight_evidence_by_type_name {
    my( $self, $type, $name ) = @_;

    my $canvas = $self->canvas;
    foreach my $obj ($canvas->find('withtag', $type)) {
        my $text = $canvas->itemcget($obj, 'text');
        if ($text eq $name) {
            $self->highlight($obj);
            last;
        }
    }
}

sub highlight {
    my $self = shift;

    $self->SUPER::highlight(@_);
    $self->canvas->SelectionOwn(
        -command    => sub{ $self->deselect_all },
        );
    weaken $self;
}

sub DESTROY {
    warn "Destrying ", ref(shift), "\n";
}

1;

__END__

=head1 NAME - CanvasWindow::EvidencePaster

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

