
### EditWindow::Clone

package EditWindow::Clone;

use strict;
use warnings;
use Carp;

use base 'EditWindow';

=pod

    -- Clone --

    clone_name  accession  sequence_version

    sequence_length  golden_start  golden_end

    -- Assembly --

    assembly_start  assembly_end  assembly_strand    

    -- Annotation --

    Keywords (Printable non-punctuation chars)

    Description

    Remarks

=cut

sub initialise {
    my ($self) = @_;

    my $top = $self->top;

    my @frame_pack = (
        -side   => 'top',
        -fill   => 'x',
        );

    my $clone_frame = $top->LabFrame(
        -label      => 'Clone',
        -border     => 3,
        )->pack(@frame_pack);

    my $info_frame = $clone_frame->Frame->pack(@frame_pack);
    $self->make_entry($info_frame, 'Name: ',            'clone_name',           14);
    $self->insert_pad($info_frame);
    $self->make_entry($info_frame, 'Accession.SV: ',    'accession_version',    13);

    $clone_frame->Frame(
        -height => 10,
        )->pack(@frame_pack);

    my $length_frame = $clone_frame->Frame->pack(@frame_pack);
    $self->make_entry($length_frame, 'Length: ',    'sequence_length',  7);
    $self->insert_pad($length_frame);
    $self->make_entry($length_frame, 'Start: ',     'golden_start',     7);
    $self->insert_pad($length_frame);
    $self->make_entry($length_frame, 'End: ',       'golden_end',       7);

    my $assembly_frame = $top->LabFrame(
        -label      => 'Assembly',
        -border     => 3,
        )->pack(@frame_pack);
    $self->make_entry($assembly_frame, 'Start: ',   'assembly_start',           8);
    $self->insert_pad($assembly_frame);
    $self->make_entry($assembly_frame, 'End: ',     'assembly_end',             8);
    $self->insert_pad($assembly_frame);
    $self->make_entry($assembly_frame, 'Strand: ',  'display_assembly_strand',  5);

    my $edit_frame = $top->LabFrame(
        -label      => 'Properties',
        -border     => 3,
        )->pack(@frame_pack, -expand => 1, -fill => 'both' );

    $self->keyword_text(
        $self->make_labelled_text_widget(
            $edit_frame, 
            "Keywords: \n(one per \nline )",     
            8,
            undef,
            undef,
            -fill => 'x')
        );

    $self->description_text(
        $self->make_labelled_text_widget(
            $edit_frame, 
            'Description: ',   
            12,
            'Generate',
            sub { $self->generate_desc },
            -expand => 1,
            -fill => 'both')
        );

    $self->remark_text(
        $self->make_labelled_text_widget(
            $edit_frame, 
            'Remarks: ',       
            4,
            undef,
            undef,
            -fill => 'x')
        );

    my $button_frame = $top->Frame->pack(@frame_pack);

    my $save = sub { $self->save };
    $button_frame->Button(
        -text       => 'Save',
        -command    => $save,
        )->pack( -side => 'left' );
    $top->bind('<Control-s>', $save);
    $top->bind('<Control-S>', $save);

    my $close_window = sub { $self->close_window };
    $button_frame->Button(
        -text       => 'Close',
        -command    => $close_window,
        )->pack( -side => 'right' );
    $top->bind('<Control-w>', $close_window);
    $top->bind('<Control-W>', $close_window);
    $top->protocol('WM_DELETE_WINDOW', $close_window);

    $top->bind('<Destroy>', sub{ my $self = undef });

    $self->fill_Entries;
    $self->fill_Properties;
    $self->set_minsize;

    return;
}

sub fill_Properties {
    my ($self) = @_;

    my ($clone) = $self->Clone
      or confess "No clone attached";

    my $key = $self->keyword_text;
    $key->delete('1.0', 'end');
    $key->insert('end', join '', map { "$_\n" } $clone->get_all_keywords);

    my $desc = $self->description_text;
    $desc->delete('1.0', 'end');
    $desc->insert('end', $clone->description);

    my $rem = $self->remark_text;
    $rem->delete('1.0', 'end');
    $rem->insert('end', join '', map { "$_\n" } $clone->get_all_remarks);

    return;
}

sub make_labelled_text_widget {
    my ($self, $widget, $name, $height, 
        $button_text, $button_cmd, @fill) = @_;

    my $std_border = 3;
    my $frame = $widget->Frame(
        -border => $std_border,
        )->pack( -side => 'top', @fill);

    my $text = $frame->Scrolled('Text',
        -scrollbars         => 'e',
        -width              => 45,
        -height             => $height,
        -exportselection    => 1,
        # -background         => 'white', ### Add to Tk defaults
        -wrap               => 'word',
        )->pack( -side => 'right', -expand => 1, @fill );

    my $tw = $text->Subwidget('text');
    $tw->bind(ref($tw), '<Key>', '');
    $tw->bind("<Key>", [\&insert_char, Tk::Ev('A')]);

    my $label_frame = $frame->Frame->pack(-side => 'right', -fill => 'y', -expand => 0);

    $label_frame->Label(
        -text       => $name,
        -anchor     => 'ne',
        -justify    => 'right',
        -width      => 12,
        )->pack(-side => 'top');

    if ($button_text) {
        $label_frame->Button(
            -text       => $button_text,
            -command    => $button_cmd,
            -anchor => 'e',
            )->pack(-side => 'top');
    }

    return $text;
}

sub generate_desc {
    my ($self) = @_;

    my $desc = $self->SessionWindow->Assembly
        ->generate_description_for_clone($self->Clone);

    unless ($desc) {
        $self->top->messageBox(
            -title      => 'otter: No description',
            -icon       => 'warning',
            -message    => "I didn't find anything to describe",
            -type       => 'OK',
            );

        return;
    }

    # delete any existing text that is highlighted (we have to eval
    # because if nothing is highlighted this errors)
    eval{$self->description_text->delete('sel.first', 'sel.last')};

    # and insert the new text at the current cursor position
    $self->description_text->insert('insert', $desc);

    return;
}

sub save {
    my ($self) = @_;

    if (my $clone = $self->get_new_Clone_if_changed) {
        $self->save_Clone($clone);
        $self->fill_Properties;
    }

    return;
}

sub save_Clone {
    my ($self, $clone) = @_;

    $self->SessionWindow->save_Clone($clone);
    $self->Clone($clone);

    return 1;
}

sub close_window {
    my ($self) = @_;

    # Check for unsaved changes
    if (my $clone = $self->get_new_Clone_if_changed) {
        # Ask the user if changes should be saved
        my $name = $clone->clone_name;
        my $dialog = $self->top->Dialog(
            -title          => 'otter: Save changes?',
            -bitmap         => 'question',
            -text           => "Save changes to Clone '$name'?",
            -default_button => 'Yes',
            -buttons        => [qw{ Yes No Cancel }],
            );
        my $ans = $dialog->Show;

        if ($ans eq 'Cancel') {
            return; # Abandon window close
        }
        elsif ($ans eq 'Yes') {
            $self->save_Clone($clone) or return;
        }
    }

    $self->top->destroy;
    return 1;
}

sub get_new_Clone_if_changed {
    my ($self) = @_;

    my $old = $self->Clone;
    my $new = $old->clone;
    $new->drop_all_keywords;
    $new->drop_all_remarks;
    $new->drop_description;

    foreach my $key ($self->get_cleaned_text($self->keyword_text)) {
        $new->add_keyword($key);
    }

    my $desc = join(' ', $self->get_cleaned_text($self->description_text));
    $new->description($desc);

    foreach my $rem ($self->get_cleaned_text($self->remark_text)) {
        $new->add_remark($rem);
    }

    # warn sprintf "\nOLD: <%s>\n\nNEW: <%s>\n\n",
    #    $old->ace_string, $new->ace_string;
    if ($old->ace_string ne $new->ace_string) {
        return $new;
    } else {
        return;
    }
}

sub get_cleaned_text {
    my ($self, $widget) = @_;

    my @text;
    foreach my $line (split /\n+/, $widget->get('1.0', 'end')) {
        next unless $line =~ /\w/;

        # Shrink whitespace into single spaces
        $line =~ s/\s+/ /g;
        # Remove any trailing or leading space
        $line =~ s/(^ | $)//g;

        push(@text, $line);
    }
    return @text;
}

sub keyword_text {
    my ($self, $keyword_text) = @_;

    if ($keyword_text) {
        $self->{'_keyword_text'} = $keyword_text;
    }
    return $self->{'_keyword_text'};
}

sub description_text {
    my ($self, $description_text) = @_;

    if ($description_text) {
        $self->{'_description_text'} = $description_text;
    }
    return $self->{'_description_text'};
}

sub remark_text {
    my ($self, $remark_text) = @_;

    if ($remark_text) {
        $self->{'_remark_text'} = $remark_text;
    }
    return $self->{'_remark_text'};
}

# Inserts (printing) characters with the same style as the rest of the line
sub insert_char {
    my ($text, $char) = @_;

    # We only want to insert printing characters in the Text box!
    # [:print:] is the POSIX class of printing characters.
    return unless $char =~ /[[:print:]]/;
    return if $char eq "\t";

    # Expected behaviour is that any selected text will
    # be replaced by what the user types.
    $text->deleteSelected;

    $text->insert('insert', $char);

    return;
}

sub fill_Entries {
    my ($self) = @_;

    my $clone = $self->Clone
      or confess "No Clone attached";
    foreach my $method (keys %{$self->{'_clone_entry'}}) {
        my $entry = $self->{'_clone_entry'}{$method};
        $entry->configure(-state => 'normal');
        my $text = $clone->$method();
        $entry->delete(0, 'end');
        $entry->insert(0, $text);

        # Not all versions of Entry have the "readonly" state
        eval { $entry->configure(-state => 'readonly'); };
        $entry->configure(-state => 'disabled') if $@;
    }

    return;
}

sub make_entry {
    my ($self, $widget, $label, $clone_method, $width) = @_;

    $width ||= 20;

    confess "Hash key '$clone_method' already in use"
      if exists $self->{'_clone_entry'}{$clone_method};

    $widget->Label(
        -text   => $label,
        -anchor => 's',
        -padx   => 6,
        )->pack(-side => 'left', -fill => 'y');
    $self->{'_clone_entry'}{$clone_method} = $widget->Entry(
        -width => $width,
        )->pack(-side => 'left');

    return;
}

sub insert_pad {
    my ($self, $widget) = @_;

    $widget->Frame(
        -width  => 10,
        )->pack(-side => 'left');

    return;
}

sub Clone {
    my ($self, $Clone) = @_;

    if ($Clone) {
        $self->{'_Clone'} = $Clone;
    }
    return $self->{'_Clone'};
}

sub SessionWindow {
    my ($self, $SessionWindow) = @_;

    if ($SessionWindow) {
        $self->{'_SessionWindow'} = $SessionWindow;
    }
    return $self->{'_SessionWindow'};
}

sub write_access {
    my ($self) = @_;

    return $self->SessionWindow->AceDatabase->write_access;
}

sub DESTROY {
    my ($self) = @_;

    my $name = $self->Clone->name;
    my $type = ref($self);
    warn "Destroying $type '$name'\n";

    return;
}

1;

__END__

=head1 NAME - EditWindow::Clone

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

