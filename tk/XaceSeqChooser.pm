
### XaceSeqChooser

package XaceSeqChooser;

use strict;
use Carp;
use CanvasWindow;
use ExonCanvas;
use vars ('@ISA');
use Hum::Ace;

@ISA = ('CanvasWindow');

sub new {
    my( $pkg, $tk ) = @_;

    my $menu_frame = $tk->Frame(
        -borderwidth    => 1,
        -relief         => 'raised',
        );
    $menu_frame->pack(
        -side   => 'top',
        -fill   => 'x',
        );
    
    my $self = $pkg->SUPER::new($tk);
    $self->menu_bar($menu_frame);

    $self->populate_menus;

    #$self->add_buttons;
    $self->bind_events;
    $self->current_state('clone');
    $self->minimum_scroll_bbox(0,0,200,200);
    return $self;
}

sub old_new {
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
    $self->minimum_scroll_bbox(0,0,200,200);
    return $self;
}

sub button_frame {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_button_frame'} = $bf;
    }
    return $self->{'_button_frame'};
}

sub menu_bar {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_menu_bar'} = $bf;
    }
    return $self->{'_menu_bar'};
}

sub set_known_GeneMethods {
    my $self = shift;
    my %methods_mutable = @_;
    
    my $ace = $self->ace_handle;
    while (my($name, $is_mutable) = each %methods_mutable) {
        my $meth_tag = $ace->fetch(Method => $name)
            or confess "Can't get Method '$name'";
        my $meth = Hum::Ace::GeneMethod->new_from_ace_tag($meth_tag);
        $meth->is_mutable($is_mutable);
        $self->add_GeneMethod($meth);
    }
}

sub add_GeneMethod {
    my( $self, $meth ) = @_;
    
    my $name = $meth->name;
    $self->{'_gene_methods'}{$name} = $meth;
}

sub get_GeneMethod {
    my( $self, $name ) = @_;
    
    if (my $meth = $self->{'_gene_methods'}{$name}) {
        return $meth;
    } else {
        confess "No such method '$name'";
    }
}

sub get_all_GeneMethods {
    my( $self ) = @_;
    
    return values %{$self->{'_gene_methods'}};
}

sub get_all_mutable_GeneMethods {
    my( $self ) = @_;
    
    return sort {lc($a->name) cmp lc($b->name)}
        grep $_->is_mutable, $self->get_all_GeneMethods;
}

sub _make_menu {
    my( $self, $name, $pos ) = @_;
    
    $pos ||= 0;
    
    my $menu_frame = $self->menu_bar
        or confess "No menu_bar";
    my $button = $menu_frame->Menubutton(
        -text       => $name,
        -underline  => $pos,
        #-padx       => 6,
        -pady       => 6,
        );
    $button->pack(
        -side       => 'left',
        );
    my $menu = $button->Menu(
        -tearoff    => 0,
        );
    $button->configure(
        -menu       => $menu,
        );
    return $menu;
}

sub populate_menus {
    my( $self ) = @_;
    
    my $menu_frame = $self->menu_bar
        or confess "No menu_bar";
    
    # Chooser menu
    my $chooser = $self->_make_menu('Chooser');
    
    $chooser->add('command',
        -label          => 'Attach Xace',
        -command        => sub {
            if (my $xwid = $self->get_xace_window_id) {
                my $xrem = Hum::Ace::XaceRemote->new($xwid);
                $self->xace_remote($xrem);
                $xrem->send_command('save');
            } else {
                warn "no xwindow id: $xwid";
            }
        },
        -accelerator    => 'Ctrl-X',
        -underline      => 0,
        );
    $chooser->add('command',
        -label          => 'Resync',
        -hidemargin     => 1,
        -command        => sub { warn "Called Resync" },
        -accelerator    => 'Ctrl-R',
        -underline      => 0,
        );
    $chooser->add('separator');
    $chooser->add('command',
        -label          => 'Exit',
        -command        => sub { $menu_frame->toplevel->destroy },
        -accelerator    => 'Ctrl-Q',
        -underline      => 0,
        );
    
    # Mode menu
    my $mode = $self->_make_menu('Mode');
    my $mode_var = 'clone';
    my $mode_switch = sub {
        $self->clone_sub_switch($mode_var);        
    };
    $mode->add('radiobutton',
        -label          => 'Clones',
        -value          => 'clone',
        -variable       => \$mode_var,
        -command        => $mode_switch,
        );
    $mode->add('radiobutton',
        -label          => 'Sub sequences',
        -value          => 'subseq',
        -variable       => \$mode_var,
        -command        => $mode_switch,
        );
    
    # Subseq menu
    my $subseq = $self->_make_menu('SubSeq');
    
    $subseq->add('command',
        -label          => 'New',
        -command        => sub{ warn "Called New" },
        -accelerator    => 'Ctrl-N',
        -underline      => 0,
        );
    $subseq->add('command',
        -label          => 'Edit',
        -command        => sub{ warn "Called Edit" },
        -accelerator    => 'Ctrl-E',
        -underline      => 0,
        );
    $subseq->add('separator');
    $subseq->add('command',
        -label          => 'Merge',
        -command        => sub{ warn "Called Merge" },
        -accelerator    => 'Ctrl-M',
        -underline      => 0,
        );
    $subseq->add('command',
        -label          => 'AutoMerge',
        -command        => sub{ warn "Called AutoMerge" },
        -accelerator    => 'Ctrl-U',
        -underline      => 0,
        );
    $subseq->add('command',
        -label          => 'Isoform',
        -command        => sub{ warn "Called Isoform" },
        -accelerator    => 'Ctrl-I',
        -underline      => 0,
        );
    $subseq->add('command',
        -label          => 'Transcript',
        -command        => sub{ warn "Called Transcript" },
        -accelerator    => 'Ctrl-T',
        -underline      => 0,
        );
}

sub add_buttons {
    my( $self, $tk ) = @_;
    
    my $bf = $self->button_frame;
    my $x_attach = $bf->Button(
        -text       => 'Attach xace',
        -command    => sub{
            if (my $xwid = $self->get_xace_window_id) {
                my $xrem = Hum::Ace::XaceRemote->new($xwid);
                $self->xace_remote($xrem);
                $xrem->send_command('save');
            } else {
                warn "no xwindow id: $xwid";
            }
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
    
    my $edit_button = $bf->Button(
        -text       => 'Edit',
        -command    => sub{
            $self->edit_subsequences;
            });
    $edit_button->pack(
        -side   => 'left',
        );
    
    my $quit_button = $bf->Button(
        -text       => 'Quit',
        -command    => sub{ $self->canvas->toplevel->destroy; },
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
    $canvas->Tk::bind('<Double-Button-1>', [
        sub{
            $self->left_button_handler(@_);
            $self->edit_double_clicked;
            },
        Tk::Ev('x'), Tk::Ev('y') ]);
}

sub edit_double_clicked {
    my( $self ) = @_;
    
    if ($self->current_state eq 'clone') {
        $self->clone_sub_switch;
    } else {
        $self->edit_subsequences;
    }
}

sub left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;

    return if $self->delete_message;

    $self->deselect_all;
    if (my $obj = $canvas->find('withtag', 'current')) {
        $self->highlight($obj);
    }
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
}

sub clone_sub_switch {
    my( $self, $new_state ) = @_;
    
    if ($new_state eq 'clone') {
        $self->switch_to_clone_display;
    }
    elsif ($new_state eq 'subseq') {
        $self->switch_to_subseq_display;   
    }
    else {
        confess "Unknown state '$new_state'";
    }
    #$self->set_window_size(1);
    $self->fix_window_min_max_sizes;
}

sub switch_to_subseq_display {
    my( $self ) = @_;
    
    my @clone_names = $self->list_selected_clone_names;
    $self->deselect_all;
    $self->canvas->delete('all');
    $self->current_state('subseq');
    $self->draw_subseq_list(@clone_names);
}

sub switch_to_clone_display {
    my( $self ) = @_;
    
    my @clone_names = $self->list_selected_clone_names;
    $self->deselect_all;
    $self->canvas->delete('all');
    $self->current_state('clone');
    $self->draw_clone_list;
    $self->highlight_by_name('clone', @clone_names);
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
    elsif (my $local = $self->local_server) {
        $adbh = $local->ace_handle;
    }
    else {
        $adbh = $self->{'_ace_database_handle'};
    }
    return $adbh;
}

sub local_server {
    my( $self, $local ) = @_;
    
    if ($local) {
        $self->{'_local_ace_server'} = $local;
    }
    return $self->{'_local_ace_server'};
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

sub edit_subsequences {
    my( $self ) = @_;
    
    my @sub_names = $self->list_selected_subseq_names;
    my $canvas = $self->canvas;
    foreach my $sub_name (@sub_names) {
        # Just show the edit window if present
        next if $self->raise_subseq_edit_window($sub_name);
        
        # Get a copy of the subseq
        my $sub = $self->get_SubSeq($sub_name)->clone;
        
        # Make a new window
        my $top = $canvas->Toplevel(
            -title  => $sub_name,
            );
        
        # Make new ExonCanvas object and initialize
        my $ec = ExonCanvas->new($top);
        $ec->name($sub_name);
        $ec->xace_seq_chooser($self);
        $ec->SubSeq($sub);
        $ec->initialize;
        
        $self->save_subseq_edit_window($sub_name, $top);
    }
}

sub raise_subseq_edit_window {
    my( $self, $name ) = @_;
    
    confess "no name given" unless $name;
    
    if (my $top = $self->{'_subseq_edit_window'}{$name}) {
        $top->deiconify;
        $top->raise;
        return 1;
    } else {
        return 0;
    }
}

sub save_subseq_edit_window {
    my( $self, $name, $top ) = @_;
    
    $self->{'_subseq_edit_window'}{$name} = $top;
}

sub delete_subseq_edit_window {
    my( $self, $name ) = @_;
    
    delete($self->{'_subseq_edit_window'}{$name});
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

sub OLD_draw_subseq_list {
    my( $self, @selected_clones ) = @_;
    
    my( @subseq );
    foreach my $clone_name (@selected_clones) {
        #warn "Fetching Subsequences for '$clone_name'\n";
        my $clone = $self->get_CloneSeq($clone_name);
        my( @gensub );
        foreach my $sub ($clone->get_all_SubSeqs) {
            push(@gensub, $sub->name);
        }
        push(@subseq, sort @gensub);
    }
    $self->draw_sequence_list('subseq', @subseq);
}

sub draw_subseq_list {
    my( $self, @selected_clones ) = @_;
    
    my( @subseq );
    foreach my $clone_name (@selected_clones) {
        my $clone = $self->get_CloneSeq($clone_name);
        foreach my $clust ($self->get_all_Subseq_clusters($clone)) {
            push(@subseq, "") if @subseq;
            push(@subseq, map($_->name, @$clust));
        }
    }
    $self->draw_sequence_list('subseq', @subseq);
}

sub draw_sequence_cluster {
    my( $self, $clust ) = @_;
    
}

sub get_all_Subseq_clusters {
    my( $self, $clone ) = @_;
    
    my @subseq = sort {$a->strand <=> $b->strand
        || $a->start <=> $b->start
        || $a->end <=> $b->end} $clone->get_all_SubSeqs;
    my $first = $subseq[0] or return;
    my( @clust );
    my $ci = 0;
    $clust[$ci] = [$first];
    my $x      = $first->start;
    my $y      = $first->end;
    my $strand = $first->strand;
    for (my $i = 1; $i < @subseq; $i++) {
        my $this = $subseq[$i];
        if ($this->strand == $strand
            and $this->start <= $y
            and $this->end   >= $x)
        {
            push(@{$clust[$ci]}, $this);
            $x = $this->start if $this->start < $x;
            $y = $this->end   if $this->end   > $y;
        } else {
            $ci++;
            $clust[$ci] = [$this];
            $x      = $this->start;
            $y      = $this->end;
            $strand = $this->strand;
        }
    }
    return sort {$a->[0]->start <=> $b->[0]->start} @clust;
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
    
    my $ace = $self->ace_handle;
    
    my $clone = Hum::Ace::CloneSeq->new;
    $clone->ace_name($clone_name);
    # Get the DNA
    my $seq = $clone->store_Sequence_from_ace_handle($ace);

    # These raw_queries are much faster than
    # fetching the whole Genome_Sequence object!
    $ace->raw_query("find Sequence $clone_name");
    my $sub_list = $ace->raw_query('show -a Subsequence');
    $sub_list =~ s/\0//g;   # Remove any nulls
    
    while ($sub_list =~ /^Subsequence\s+"([^"]+)"\s+(\d+)\s+(\d+)/mg) {
        my($name, $start, $end) = ($1, $2, $3);
        eval{
            my $t_seq = $ace->fetch(Sequence => $name);
            my $sub = Hum::Ace::SubSeq
                ->new_from_name_start_end_transcript_seq(
                    $name, $start, $end, $t_seq,
                    );
            $sub->clone_Sequence($seq);
            
            if (my $mt = $t_seq->at('Method[1]')) {
                if (my $meth = $self->get_GeneMethod($mt->name)) {
                    $sub->GeneMethod($meth);
                }
            }
            
            $clone->add_SubSeq($sub);
            $self->add_SubSeq($sub);
        };
        if ($@) {
            warn("Error fetching '$name' ($start - $end):\n", $@);
        }
    }
    return $clone;
}

sub replace_SubSeq {
    my( $self, $sub ) = @_;
    
    my $sub_name = $sub->name;
    my $clone_name = $sub->clone_Sequence->name;
    my $clone = $self->get_CloneSeq($clone_name);
    $clone->replace_SubSeq($sub);
    $self->{'_subsequence_cache'}{$sub_name} = $sub;
}

sub add_SubSeq {
    my( $self, $sub ) = @_;
    
    my $name = $sub->name;
    if ($self->{'_subsequence_cache'}{$name}) {
        confess "already have SubSeq '$name'";
    } else {
        $self->{'_subsequence_cache'}{$name} = $sub;
    }
}

sub get_SubSeq {
    my( $self, $name ) = @_;
    
    confess "no name given" unless $name;
    return $self->{'_subsequence_cache'}{$name};
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
        if (my $text = $slist[$i]) {
            $canvas->createText(
                $x, $y,
                -anchor     => 'nw',
                -text       => $text,
                -font       => [$font, $size, 'bold'],
                -tags       => [$tag],
                );
        }
        
        if (($i + 1) % 20) {
            $y += $size + $pad;
        } else {
            $y = 0;
            my $x_max = ($canvas->bbox($tag))[2];
            $x = $x_max + ($size * 2);
        }
    }
}

sub xace_remote {
    my( $self, $xrem ) = @_;
    
    if ($xrem) {
        my $expected = 'Hum::Ace::XaceRemote';
        confess "'$xrem' is not an '$expected'"
            unless (ref($xrem) and $xrem->isa($expected));
        $self->{'_xace_remote'} = $xrem;
    }
    return $self->{'_xace_remote'};
}

sub get_xace_window_id {
    my( $self ) = @_;
    
    my $mid = $self->message("Please click on the xace main window with the cross-hairs");
    $self->delete_message($mid);
    local *XWID;
    open XWID, "xwininfo |"
        or confess("Can't open pipe from xwininfo : $!");
    my( $xwid );
    while (<XWID>) {
        # xwininfo: Window id: 0x7c00026 "ACEDB 4_9c, lace bA314N13"
        if (/Window id: (\w+) "([^"]+)/) {
            my $id   = $1;
            my $name = $2;
            if ($name =~ /^ACEDB/) {
                $xwid = $id;
                $self->message("Attached to:\n$name");
            } else {
                $self->message("'$name' is not an xace main window");
            }
        }
    }
    if (close XWID) {
        return $xwid;
    } else {
        $self->message("Error running xwininfo: $?");
    }
}

{
    my %state_label = (
        'clone'     => 1,
        'subseq'    => 1,
        );

    sub current_state {
        my( $self, $state ) = @_;

        if ($state) {
            unless ($state_label{$state}) {
                confess "Not a permitted state '$state'";
            }
            $self->{'_current_state'} = $state;
        }
        return $self->{'_current_state'};
    }
}

sub highlight_by_name {
    my( $self, $tag, @names ) = @_;
    
    my $canvas = $self->canvas;
    my %selected_clone = map {$_, 1} @names;
    
    my( @obj );
    foreach my $cl ($canvas->find('withtag', $tag)) {
        my $n = $canvas->itemcget($cl, 'text');
        if ($selected_clone{$n}) {
            push(@obj, $cl);
        }
    }
    
    $self->highlight(@obj);
}

sub list_selected_clone_names {
    my( $self ) = @_;

    my( @names );
    if ($self->current_state eq 'clone') {
        my $canvas = $self->canvas;
        foreach my $obj ($self->list_selected) {
            if (grep $_ eq 'clone', $canvas->gettags($obj)) {
                my $n = $canvas->itemcget($obj, 'text');
                push(@names, $n);
            }
        }
        $self->{'_selected_clone_list'} = [@names];
    }
    elsif (my $nam = $self->{'_selected_clone_list'}) {
        @names = @$nam;
    }
    return @names;
}

sub list_selected_subseq_names {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my( @names );
    foreach my $obj ($self->list_selected) {
        if (grep $_ eq 'subseq', $canvas->gettags($obj)) {
            my $n = $canvas->itemcget($obj, 'text');
            push(@names, $n);
        }
    }
    return @names;
}


1;

__END__

=head1 NAME - XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

