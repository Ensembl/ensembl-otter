
### MenuCanvasWindow::XaceSeqChooser

package MenuCanvasWindow::XaceSeqChooser;

use strict;
use Carp;
use MenuCanvasWindow;
use MenuCanvasWindow::ExonCanvas;
use vars ('@ISA');
use Hum::Ace;

@ISA = ('MenuCanvasWindow');

sub new {
    my( $pkg, $tk ) = @_;
    
    my $self = $pkg->SUPER::new($tk);

    $self->populate_menus;
    $self->bind_events;
    $self->minimum_scroll_bbox(0,0,200,200);
    return $self;
}

sub menu_bar {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_menu_bar'} = $bf;
    }
    return $self->{'_menu_bar'};
}

sub subseq_menubutton {
    my( $self, $smb ) = @_;
    
    if ($smb) {
        $self->{'_subseq_menubutton'} = $smb;
    }
    return $self->{'_subseq_menubutton'};
}

sub clone_sub_switch_var {
    my( $self, $switch_ref ) = @_;
    
    if ($switch_ref) {
        $self->{'_clone_sub_switch_var'} = $switch_ref;
    }
    return $self->{'_clone_sub_switch_var'};
}

sub set_known_GeneMethods {
    my $self = shift;
    my %methods_mutable = @_;
    
    my $ace = $self->ace_handle;
    while (my($name, $is_mutable) = each %methods_mutable) {
        my $meth_tag = $ace->fetch(Method => $name);
        unless ($meth_tag) {
            warn "Method '$name' is not in database\n";
            next;
        }
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

sub get_default_mutable_GeneMethod {
    my( $self ) = @_;
    
    my @possible = grep $_->is_coding, $self->get_all_mutable_GeneMethods;
    if (@possible)  {
        return $possible[0];
    } else {
        $self->message("Unable to get a default GeneMethod");
        return;
    }
}

sub make_menu {
    my( $self, $name, $pos ) = @_;
    
    $pos ||= 0;
    
    my $menu_frame = $self->menu_bar
        or confess "No menu_bar";
    my $button = $menu_frame->Menubutton(
        -text       => $name,
        -underline  => $pos,
        #-padx       => 8,
        #-pady       => 6,
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

sub attach_xace {
    my( $self ) = @_;
    
    if (my $xwid = $self->get_xace_window_id) {
        my $xrem = Hum::Ace::XaceRemote->new($xwid);
        $self->xace_remote($xrem);
        $xrem->send_command('save');
    } else {
        warn "no xwindow id: $xwid";
    }
}

sub populate_menus {
    my( $self ) = @_;
    
    my $menu_frame = $self->menu_bar
        or confess "No menu_bar";
    my $top = $menu_frame->toplevel;
    
    # File menu
    my $file = $self->make_menu('File');
    
    # Attach xace
    my $xace_attach_command = sub { $self->attach_xace };
    $file->add('command',
        -label          => 'Attach Xace',
        -command        => $xace_attach_command,
        -accelerator    => 'Ctrl+X',
        -underline      => 0,
        );
    $top->bind('<Control-x>', $xace_attach_command);
    $top->bind('<Control-X>', $xace_attach_command);
   
    # Resync with database
    my $resync_command = sub { $self->resync_with_db };
    $file->add('command',
        -label          => 'Resync',
        -hidemargin     => 1,
        -command        => $resync_command,
        -accelerator    => 'Ctrl+R',
        -underline      => 0,
        );
    $top->bind('<Control-r>', $resync_command);
    $top->bind('<Control-R>', $resync_command);
    
    $file->add('separator');
    
    # Quit
    my $exit_command = sub { $menu_frame->toplevel->destroy };
    $file->add('command',
        -label          => 'Exit',
        -command        => $exit_command,
        -accelerator    => 'Ctrl+Q',
        -underline      => 0,
        );
    $top->bind('<Control-q>', $exit_command);
    $top->bind('<Control-Q>', $exit_command);
    
    # Show menu
    my $mode = $self->make_menu('Show');
    my $mode_var = 'clone';
    $self->clone_sub_switch_var(\$mode_var);
    my $mode_switch = sub {
        $self->switch_state;
    };
    
    $mode->add('radiobutton',
        -label          => 'Clones',
        -value          => 'clone',
        -variable       => \$mode_var,
        -command        => $mode_switch,
        );
    $mode->add('radiobutton',
        -label          => 'SubSequences',
        -value          => 'subseq',
        -variable       => \$mode_var,
        -command        => $mode_switch,
        );
    
    # Subseq menu
    my $subseq = $self->make_menu('SubSeq');
    $self->subseq_menubutton($subseq->parent);
    
    # New subsequence
    my $new_command = sub{ $self->edit_new_subsequence };
    $subseq->add('command',
        -label          => 'New',
        -command        => $new_command,
        -accelerator    => 'Ctrl+N',
        -underline      => 0,
        );
    $top->bind('<Control-n>', $new_command);
    $top->bind('<Control-N>', $new_command);
    
    # Edit subsequence
    my $edit_command = sub{ $self->edit_subsequences };
    $subseq->add('command',
        -label          => 'Edit',
        -command        => $edit_command,
        -accelerator    => 'Ctrl+E',
        -underline      => 0,
        );
    $top->bind('<Control-e>', $edit_command);
    $top->bind('<Control-E>', $edit_command);
    
    # Delete subsequence
    my $delete_command = sub { $self->delete_subsequences };
    $subseq->add('command',
        -label          => 'Delete',
        -command        => $delete_command,
        -accelerator    => 'Ctrl+D',
        -underline      => 0,
        );
    $top->bind('<Control-d>', $delete_command);
    $top->bind('<Control-D>', $delete_command);
    
    $subseq->add('separator');
    $subseq->add('command',
        -label          => 'Merge',
        -command        => sub{ warn "Called Merge" },
        -accelerator    => 'Ctrl+M',
        -underline      => 0,
        -state          => 'disabled',
        );
    $subseq->add('command',
        -label          => 'AutoMerge',
        -command        => sub{ warn "Called AutoMerge" },
        -accelerator    => 'Ctrl+U',
        -underline      => 0,
        -state          => 'disabled',
        );
    
    my $isoform_command = sub{ $self->make_isoform_subsequence };
    $subseq->add('command',
        -label          => 'Isoform',
        -command        => $isoform_command,
        -accelerator    => 'Ctrl+I',
        -underline      => 0,
        );
    $top->bind('<Control-i>', $isoform_command);
    $top->bind('<Control-I>', $isoform_command);
    
    # What did I intend this command to do?
    #$subseq->add('command',
    #    -label          => 'Transcript',
    #    -command        => sub{ warn "Called Transcript" },
    #    -accelerator    => 'Ctrl+T',
    #    -underline      => 0,
    #    );
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
    
    $canvas->Tk::bind('<Escape>',   sub{ $self->deselect_all        });    
    $canvas->Tk::bind('<Return>',   sub{ $self->edit_double_clicked });    
    $canvas->Tk::bind('<KP_Enter>', sub{ $self->edit_double_clicked });    
    
}

sub edit_double_clicked {
    my( $self ) = @_;
    
    if ($self->current_state eq 'clone') {
        $self->save_selected_clone_names;
        $self->current_state('subseq');
        $self->draw_current_state;
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

sub switch_state {
    my( $self ) = @_;
    
    my $state = $self->current_state;
    if ($state eq 'subseq') {
        # We are going from clone to subseq so we
        # need to save the highlighted clone names
        $self->save_selected_clone_names;
    }
    $self->draw_current_state;
}

sub draw_current_state {
    my( $self ) = @_;
    
    my $state = $self->current_state;
    if ($state eq 'clone') {
        $self->do_clone_display;
    }
    else {
        $self->do_subseq_display;   
    }
    $self->fix_window_min_max_sizes;
}

sub do_subseq_display {
    my( $self ) = @_;
        
    my @clone_names = $self->list_selected_clone_names;
    $self->deselect_all;
    $self->canvas->delete('all');
    $self->draw_subseq_list(@clone_names);
}

sub do_clone_display {
    my( $self ) = @_;
        
    my @clone_names = $self->list_selected_clone_names;
    $self->deselect_all;
    $self->canvas->delete('all');
    $self->draw_clone_list;
    $self->highlight_by_name('clone', @clone_names);
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

sub resync_with_db {
    my( $self ) = @_;
    
    
    if ($self->list_all_subseq_edit_window_names) {
        $self->message("All the Subsequence edit windows must be closed before a ReSync");
        return;
    }
    
    $self->canvas->Busy(
        -recurse => 0,
        );
    
    # Disconnect aceperl
    $self->{'_ace_database_handle'} = undef;

    if (my $local = $self->local_server) {
        $local->restart_server;
    }
    
    $self->empty_CloneSeq_cache;
    $self->empty_SubSeq_cache;
    
    # Redisplay
    $self->draw_current_state;
    
    $self->canvas->Unbusy;
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
    my( $self, @sub_names ) = @_;
    
    @sub_names = $self->list_selected_subseq_names
        unless @sub_names;
    foreach my $sub_name (@sub_names) {
        # Just show the edit window if present
        next if $self->raise_subseq_edit_window($sub_name);
        
        # Get a copy of the subseq
        my $sub = $self->get_SubSeq($sub_name);
        my $edit = $sub->clone;
        $edit->is_archival($sub->is_archival);
        
        $self->make_exoncanvas_edit_window($edit);
    }
}

sub edit_new_subsequence {
    my( $self ) = @_;
    
    my @sub_names = $self->list_selected_subseq_names;
    my( %clone_names );
    foreach my $sn (@sub_names) {
        my $sub = $self->get_SubSeq($sn);
        my $seq_name = $sub->clone_Sequence->name;
        $clone_names{$seq_name} = 1;
    }
    my @clone_n = keys %clone_names;

    my @selected_clone = $self->list_selected_clone_names;
    my      @all_clone = $self->clone_list;
    
    my( $clone_name );
    if (@clone_n == 1) {
        $clone_name = $clone_n[0];
    }
    elsif (@selected_clone == 1) {
        $clone_name = $selected_clone[0];
    }
    elsif (@all_clone == 1) {
        $clone_name = $all_clone[0];
    }
    else {
       $self->message("Unable to determine clone name");
       return;
    }
    
    # Now get the maximum transcript number for this root
    my $clone = $self->get_CloneSeq($clone_name);
    my $regex = qr{^$clone_name\.(\d+)}; # Perl 5.6 feature!
    my $max = 0;
    foreach my $sub_name (map $_->name, $clone->get_all_SubSeqs) {
        my ($n) = $sub_name =~ /$regex/;
        if ($n and $n > $max) {
            $max = $n;
        }
    }
    $max++;
    
    my $seq_name = "$clone_name.$max";
    
    # Check we don't already have a sequence of this name
    if ($self->get_SubSeq($seq_name)) {
        # Should be impossible!
        confess "Already have SubSeq named '$seq_name'";
    }

    warn "Making '$seq_name'\n";
    my( $new );
    if (@sub_names) {
        $new = $self->get_SubSeq($sub_names[0])->clone;
        for (my $i = 1; $i < @sub_names; $i++) {
            my $extra_sub = $self->get_SubSeq($sub_names[$i])->clone;
            foreach my $ex ($extra_sub->get_all_Exons) {
                $new->add_Exon($ex);
            }
        }
    }
    else {
        $new = Hum::Ace::SubSeq->new;
        $new->strand(1);
        $new->clone_Sequence($clone->Sequence);
        
        # Need to have at least 1 exon
        my $ex = $new->new_Exon;
        $ex->start(1);
        $ex->end  (2);
        
        my $gm = $self->get_default_mutable_GeneMethod
            or return;
        $new->GeneMethod($gm);
    }
    $new->name($seq_name);
    $self->add_SubSeq($new);
    $clone->add_SubSeq($new);

    $self->do_subseq_display;
    $self->highlight_by_name('subseq', $seq_name);
    
    $self->make_exoncanvas_edit_window($new);
}

sub delete_subsequences {
    my( $self ) = @_;
    
    my $xr = $self->xace_remote;
    unless ($xr) {
        $self->message('No xace attached');
        return;
    }
    
    # Make a list of editable SubSeqs from those selected,
    # which we are therefore allowed to delete.
    my @sub_names = $self->list_selected_subseq_names;
    my( @to_die );
    foreach my $sub_name (@sub_names) {
        my $sub = $self->get_SubSeq($sub_name);
        if ($sub->GeneMethod->is_mutable) {
            push(@to_die, $sub);
        }
    }
    return unless @to_die;

    # Check that none of the sequences to be deleted are being edited    
    my $in_edit = 0;
    foreach my $sub (@to_die) {
        $in_edit += $self->raise_subseq_edit_window($sub->name);
    }
    if ($in_edit) {
        $self->message("Must close edit windows before calling delete");
        return;
    }
    
    # Check that the user really wants to delete them
    
    my( $question );
    if (@to_die > 1) {
        $question = join('',
            "Really delete these subsequences?\n\n",
            map("  $_\n", map($_->name, @to_die)),
            );
    } else {
        $question = "Really delete this subsequence?\n\n  "
            . $to_die[0]->name ."\n";
    }
    my $dialog = $self->canvas->toplevel->Dialog(
        -title          => 'Delete subsequenes?',
        -bitmap         => 'question',
        -text           => $question,
        -default_button => 'Yes',
        -buttons        => [qw{ Yes No }],
        );
    my $ans = $dialog->Show;

    return if $ans eq 'No';
    
    # Make ace delete command for subsequences
    my $ace = '';
    foreach my $sub (@to_die) {
        my $sub_name   = $sub->name;
        my $clone_name = $sub->clone_Sequence->name;
        $ace .= qq{\n\-D Sequence "$sub_name"\n}
            . qq{\nSequence "$clone_name"\n}
            . qq{-D Subsequence "$sub_name"\n};
    }
    
    # Delete from acedb database
    $xr->load_ace($ace);
    $xr->save;
    
    # Remove from our objects
    foreach my $sub (@to_die) {
        $self->delete_SubSeq($sub);
    }
    
    $self->draw_current_state;
}

sub make_isoform_subsequence {
    my( $self ) = @_;
    
    my $xr = $self->xace_remote;
    unless ($xr) {
        $self->message("no xace attached");
        return;
    }
    
    my @sub_names = $self->list_selected_subseq_names;
    unless (@sub_names) {
        $self->message("No subsequence selected");
        return;
    }
    elsif (@sub_names > 1) {
        $self->message("Can't make more an Isoform from more than one selected sequence");
        return;
    }
    my $name = $sub_names[0];
    my $sub = $self->get_SubSeq($name);
    
    # Work out a name for the new isoform
    my $clone_name = $sub->clone_Sequence->name;
    my( $new_name, $iso_name );
    if ($name =~ /^$clone_name\.(.+)/) {
        my $suffix = $1;

        my @numbers = $suffix =~ /(\d+)/g;
        warn "numbers = [@numbers]";
        my ($extn) = $suffix =~ /\.([_a-zA-Z]+)$/;

        if (@numbers > 2) {
            $self->message("Got too many numbers (@numbers) from extension");
            return;
        }
        elsif (@numbers == 2) {
            # Are making an isoform of an exisiting isoform
            $new_name = $name;
            for (my $i = $numbers[1] + 1; ; $i++) {
                $iso_name = join('.', $clone_name, $numbers[0], $i);
                $iso_name .= $3 if $3;
                last unless $self->get_SubSeq($iso_name);
            }
        }
        elsif (@numbers == 1) {
            # Are making the first isoform
            $new_name = join('.', $clone_name, $numbers[0], 1);
            $iso_name = join('.', $clone_name, $numbers[0], 2);
            if ($extn) {
                $new_name .= ".$extn";
                $iso_name .= ".$extn";
            }
        }
        else {
            $self->message("Extension contains no numbers");
            return;
        }
    } else {
        # We're dealing with a non-standard name
        $self->message("SubSequence name doesn't match clone name '$clone_name'!");
        $new_name = "$name.1";
        $iso_name = "$name.2";
    }
    
    # Check we don't already have the isoform we are trying to create
    if ($self->get_SubSeq($iso_name)) {
        $self->message("Tried to create isoform '$iso_name', but it already exists!");
        return;
    }
    
    # Rename the existing subseq
    if ($new_name ne $name) {
        if ($self->raise_subseq_edit_window($name)) {
            $self->message("Please close the edit window for '$name' first");
            return;
        }
        if ($self->get_SubSeq($new_name)) {
            $self->message("Can't make isoform of '$name' because '$new_name' already exists!");
            return;
        }
        my $ec = $self->make_exoncanvas_edit_window($sub);
        $ec->set_subseq_name($new_name);
        $ec->xace_save($ec->new_SubSeq_from_tk);
    }
    
    # Make the isoform
    my $iso = $sub->clone;
    $iso->name($iso_name);
    $self->add_SubSeq($iso);
    $self->get_CloneSeq($clone_name)->add_SubSeq($iso);
    
    $self->draw_current_state;
    $self->highlight_by_name('subseq', $new_name, $iso_name);
    $self->edit_subsequences($iso_name);
}

sub make_exoncanvas_edit_window {
    my( $self, $sub ) = @_;
    
    my $sub_name = $sub->name;
    my $canvas = $self->canvas;
    
    # Make a new window
    my $top = $canvas->Toplevel;
    
    # Make new MenuCanvasWindow::ExonCanvas object and initialize
    my $ec = MenuCanvasWindow::ExonCanvas->new($top);
    $ec->name($sub_name);
    $ec->xace_seq_chooser($self);
    $ec->SubSeq($sub);
    $ec->initialize;
    
    $self->save_subseq_edit_window($sub_name, $top);
    
    return $ec;
}

sub raise_subseq_edit_window {
    my( $self, $name ) = @_;
    
    confess "no name given" unless $name;
    
    if (my $top = $self->get_subseq_edit_window($name)) {
        $top->deiconify;
        $top->raise;
        return 1;
    } else {
        return 0;
    }
}

sub get_subseq_edit_window {
    my( $self, $name ) = @_;
    
    return $self->{'_subseq_edit_window'}{$name};
}

sub list_all_subseq_edit_window_names {
    my( $self ) = @_;
    
    return keys %{$self->{'_subseq_edit_window'}};
}

sub save_subseq_edit_window {
    my( $self, $name, $top ) = @_;
    
    $self->{'_subseq_edit_window'}{$name} = $top;
}

sub delete_subseq_edit_window {
    my( $self, $name ) = @_;
    
    delete($self->{'_subseq_edit_window'}{$name});
}

sub rename_subseq_edit_window {
    my( $self, $old_name, $new_name ) = @_;
    
    my $win = $self->get_subseq_edit_window($old_name)
        or return;
    $self->delete_subseq_edit_window($old_name);
    $self->save_subseq_edit_window($new_name, $win);
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
    $self->subseq_menubutton->configure(-state => 'disabled');
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
    $self->subseq_menubutton->configure(-state => 'normal');
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
    
    my $canvas = $self->canvas;
    
    my( $clone );
    unless ($clone = $self->{'_clone_sequences'}{$clone_name}) {
        use Time::HiRes 'gettimeofday';
        my $before = gettimeofday();
        $canvas->Busy(
            -recurse => 0,
            );
        $clone = $self->express_clone_and_subseq_fetch($clone_name);
        my $after  = gettimeofday();
        $canvas->Unbusy;
        printf "Express fetch for '%s' took %4.3f\n", $clone_name, $after - $before;
        $self->{'_clone_sequences'}{$clone_name} = $clone;
    }
    return $clone;
}

sub empty_CloneSeq_cache {
    my( $self ) = @_;
    
    $self->{'_clone_sequences'} = undef;
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
            my $t_seq = $ace->fetch(Sequence => $name)
                or die "No such Subsequence '$name'\n";
            my $sub = Hum::Ace::SubSeq
                ->new_from_name_start_end_transcript_seq(
                    $name, $start, $end, $t_seq,
                    );
            $sub->clone_Sequence($seq);
            
            # Flag that the sequence is in the db
            $sub->is_archival(1);
            
            if (my $mt = $t_seq->at('Method[1]')) {
                if (my $meth = $self->get_GeneMethod($mt->name)) {
                    $sub->GeneMethod($meth);
                }
            }
            
            $clone->add_SubSeq($sub);
            $self ->add_SubSeq($sub);
        };
        if ($@) {
            warn("Error fetching '$name' ($start - $end):\n", $@);
        }
    }
    return $clone;
}

sub replace_SubSeq {
    my( $self, $sub, $old_name ) = @_;
    
    my $sub_name = $sub->name;
    $old_name ||= $sub_name;
    my $clone_name = $sub->clone_Sequence->name;
    my $clone = $self->get_CloneSeq($clone_name);
    $clone->replace_SubSeq($sub, $old_name);
    if ($sub_name ne $old_name) {
        $self->{'_subsequence_cache'}{$old_name} = undef;
        $self->rename_subseq_edit_window($old_name, $sub_name);
    }
    $self->{'_subsequence_cache'}{$sub_name} = $sub;
    $self->draw_current_state;
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

sub delete_SubSeq {
    my( $self, $sub ) = @_;
    
    my $name = $sub->name;
    my $clone_name = $sub->clone_Sequence->name;
    my $clone = $self->get_CloneSeq($clone_name);
    $clone->delete_SubSeq($name);
    
    if ($self->{'_subsequence_cache'}{$name}) {
        $self->{'_subsequence_cache'}{$name} = undef;
        return 1;
    } else {
        return 0;
    }
}

sub get_SubSeq {
    my( $self, $name ) = @_;
    
    confess "no name given" unless $name;
    return $self->{'_subsequence_cache'}{$name};
}

sub empty_SubSeq_cache {
    my( $self ) = @_;
    
    $self->{'_subsequence_cache'} = undef;
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

        my $s_var = $self->clone_sub_switch_var;
        if ($state) {
            unless ($state_label{$state}) {
                confess "Not a permitted state '$state'";
            }
            $$s_var = $state;
        }
        return $$s_var;
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

sub save_selected_clone_names {
    my( $self ) = @_;

    my $canvas = $self->canvas;
    my( @names );
    foreach my $obj ($self->list_selected) {
        if (grep $_ eq 'clone', $canvas->gettags($obj)) {
            my $n = $canvas->itemcget($obj, 'text');
            push(@names, $n);
        }
    }
    $self->{'_selected_clone_list'} = [@names];
}

sub list_selected_clone_names {
    my( $self ) = @_;

    if (my $n = $self->{'_selected_clone_list'}) {
        return @$n;
    } else {
        return;
    }
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

=head1 NAME - MenuCanvasWindow::XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

