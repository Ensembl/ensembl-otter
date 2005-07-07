
### MenuCanvasWindow::ExonCanvas

package MenuCanvasWindow::ExonCanvas;

use strict;
use Carp;
use Tk::Dialog;
use Tk::ROText;
use Tk::LabFrame;
use Tk::ComboBox;
use Hum::Ace::SubSeq;
use Hum::Translator;
use MenuCanvasWindow;
use Hum::Ace::DotterLauncher;
use Evi::EviDisplay;
use vars ('@ISA');
use Hum::Ace;
use Bio::Otter::Converter;
@ISA = ('MenuCanvasWindow');

# "new" is in MenuCanvasWindow

sub initialize {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $top = $canvas->toplevel;

    $self->draw_subseq;

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
    my $window_close = sub {
        $self->window_close or return;
        
        #  Have to specifically undef $self here, or the    #
        #  MenuCanvasWindow::ExonCanvas object doesn't get  #
        #  destroyed, because the closures in this scope    #
        #  still reference it.                              #
        $self = undef;
        };

    my $file_menu = $self->make_menu('File');
    
    # Show the subsequence in fMap
    my $show_subseq = sub{ $self->show_subseq };
    $file_menu->add('command',
        -label          => 'Show SubSequence',
        -command        => $show_subseq,
        -accelerator    => 'Ctrl+H',
        -underline      => 1,
        );
    $canvas->Tk::bind('<Control-h>',   $show_subseq);
    $canvas->Tk::bind('<Control-H>',   $show_subseq);

    # Show the peptide
    my $show_pep_command = sub{ $self->show_peptide };
    $file_menu->add('command',
        -label          => 'Show Peptide',
        -command        => $show_pep_command,
        -accelerator    => 'Ctrl+Spacebar',
        -underline      => 5,
        );
    $top->bind('<Control-p>',       $show_pep_command);
    $top->bind('<Control-P>',       $show_pep_command);
    $top->bind('<Control-space>',   $show_pep_command);
    
    # Run dotter
    my $run_dotter = sub{ $self->run_dotter };
    $file_menu->add('command',
        -label          => 'Dotter',
        -command        => $run_dotter,
        -accelerator    => 'Ctrl+.',
        -underline      => 0,
        );
    $top->bind('<Control-period>',  $run_dotter);
    $top->bind('<Control-greater>', $run_dotter);
    
    # Trap window close
    $top->protocol('WM_DELETE_WINDOW', $window_close);
    $top->bind('<Control-w>',   $window_close);
    $top->bind('<Control-W>',   $window_close);

    my $edit_menu = $self->make_menu('Edit');
    
    # Select all positions
    $edit_menu->add('command',
        -label          => 'Select All',
        -command        => $select_all_sub,
        -accelerator    => 'Ctrl+A',
        -underline      => 7,
        );
    $canvas->Tk::bind('<Control-a>', $select_all_sub);
    $canvas->Tk::bind('<Control-A>', $select_all_sub);
    
    
    # Deselect all
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    #if ($self->is_mutable && $self->xace_seq_chooser->write_access) {
    if ($self->is_mutable) {

### Commented out for tropicalis cDNA annotation workshop
#        # Select supporting evidence for the transcript
#        my $select_evidence = sub{ $self->select_evidence };
#        $file_menu->add('command',
#            -label          => 'Select evidence',
#            -command        => $select_evidence,
#            -accelerator    => 'Ctrl+E',
#            -underline      => 1,
#            );
#        $canvas->Tk::bind('<Control-e>',   $select_evidence);
#        $canvas->Tk::bind('<Control-E>',   $select_evidence);

        # Save into db via xace
        my $save_command = sub{ $self->save_if_changed };
        $file_menu->add('command',
            -label          => 'Save',
            -command        => $save_command,
            -accelerator    => 'Ctrl+S',
            -underline      => 0,
            );
        $top->bind('<Control-s>',   $save_command);
        $top->bind('<Control-S>',   $save_command);
        $top->bind('<Return>',      $save_command);
        $top->bind('<KP_Enter>',    $save_command);

        ### Additions to Edit menu

        # Flip strands
        my $reverse_command = sub { $self->toggle_tk_strand };
        $edit_menu->add('command',
            -label          => 'Reverse',
            -command        => $reverse_command,
            -accelerator    => 'Ctrl+R',
            -underline      => 1,
            );
        $canvas->Tk::bind('<Control-r>', $reverse_command);
        $canvas->Tk::bind('<Control-R>', $reverse_command);

        # Trim CDS coords to first stop character
        my $trim_cds_sub = sub { $self->trim_cds_coord_to_first_stop };
        $edit_menu->add('command',
            -label          => 'Trim CDS',
            -command        => $trim_cds_sub,
            -accelerator    => 'Ctrl+T',
            -underline      => 1,
            );
        $canvas->Tk::bind('<Control-t>', $trim_cds_sub);
        $canvas->Tk::bind('<Control-T>', $trim_cds_sub);
        
        # Add editing facilities for editable SubSeqs
        $edit_menu->add('separator');

        # Sort the positions
        my $sort_command = sub{ $self->sort_all_coordinates };
        $edit_menu->add('command',
            -label          => 'Sort',
            -command        => $sort_command,
            -accelerator    => 'Ctrl+O',
            -underline      => 1,
            );
        $top->bind('<Control-o>',   $sort_command);
        $top->bind('<Control-O>',   $sort_command);
        
        # Merge overlapping exon coordinates
        $edit_menu->add('command',
            -label          => 'Merge',
            -command        => sub{ $self->merge_position_pairs },
            -accelerator    => 'Ctrl+M',
            -underline      => 0,
            );

        # Delete selected Exons
        my $delete_exons = sub{ $self->delete_selected_exons };
        $edit_menu->add('command',
            -label          => 'Delete',
            -command        => $delete_exons,
            -accelerator    => 'Ctrl+D',
            -underline      => 0,
            );
        $canvas->Tk::bind('<Control-d>', $delete_exons);
        $canvas->Tk::bind('<Control-D>', $delete_exons);

        # Keyboard editing commands
        $canvas->Tk::bind('<Left>',      sub{ $self->canvas_text_go_left   });
        $canvas->Tk::bind('<Right>',     sub{ $self->canvas_text_go_right  });
        $canvas->Tk::bind('<BackSpace>', sub{ $self->canvas_backspace      });
        
        # For entering digits into the text object which has keyboard focus
        $canvas->eventAdd('<<digit>>', map "<KeyPress-$_>", 0..9);
        $canvas->Tk::bind('<<digit>>', [sub{ $self->canvas_insert_character(@_) }, Tk::Ev('A')]);

        # Increases the number which has keyboard focus
        $canvas->eventAdd('<<increment>>', qw{ <Up> <plus> <KP_Add> <equal> });
        $canvas->Tk::bind('<<increment>>', sub{ $self->increment_int });

        # Decreases the number which has keyboard focus
        $canvas->eventAdd('<<decrement>>', qw{ <Down> <minus> <KP_Subtract> <underscore> });
        $canvas->Tk::bind('<<decrement>>', sub{ $self->decrement_int });

        # Control-Left mouse for switching strand
        $canvas->Tk::bind('<Control-Button-1>', sub{
            $self->control_left_button_handler;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });

        # Middle mouse pastes in coords from clipboard
        $canvas->Tk::bind('<Button-2>', sub{
            $self->middle_button_paste;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });
        
        # Handle left mouse
        $canvas->Tk::bind('<Button-1>', sub{
            $self->left_button_handler;
            $self->focus_on_current_text;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });

        my $frame = $canvas->toplevel->LabFrame(
            -label => 'Transcript',
            -border => 3,
            )->pack(
                -side => 'top',
                -fill => 'x',
                );
        
        # Widget for changing name
        $self->add_subseq_rename_widget($frame);

        # Choice of Method
        my $current_method = $self->SubSeq->GeneMethod->name;
        $self->method_name_var(\$current_method);
        my @mutable_gene_methods = $self->xace_seq_chooser->get_all_mutable_GeneMethods;
        my( @menu_items );
        my $label_width = 0;
        for (my $i = 0; $i < @mutable_gene_methods; $i++) {
            my $gm = $mutable_gene_methods[$i];
            my $name = $gm->name;
            $label_width = length($name) if length($name) > $label_width;
            my( $display_name );
            if ($gm->has_parent) {
                $display_name = '    ' . $name;
            } else {
                $display_name = $name;
                unless ($i == 0) {
                    push @menu_items , '-' ;
                }
            }
            push(@menu_items,
                ['command' => $display_name, 
                    -command => sub{
                        my $txt = $self->method_name_var;
                        $$txt = $name;
                        $self->draw_translation_region;
                        $top->focus;  # Need this
                    }]
                );
        }

        # Widget for changing transcript type
        my $type_frame = $frame->Frame(
            -border => 3,
            )->pack( -side => 'top' );
        $type_frame->Label(
            -padx => 6,
            -text => 'Type:',
            )->pack( -side => 'left' );

        # Button for chosing transcript type
        $type_frame->Menubutton(
            -bitmap => '@' . Tk->findINC('cbxarrow.xbm'),
            -tearoff    =>  0 ,
            -direction  => 'below',
            -relief     => 'raised',
            -menuitems  => [@menu_items]   
            )->pack(
                -side   => 'left',
                -fill   => 'y',
                -expand => 1,
                -ipady  => 3,
                -ipadx  => 1,
                -padx   => 2,
                );

        $type_frame->Label(
            -padx => 3,
            -pady => 3,
            -anchor => 'w',
            -relief => 'sunken',
            -textvariable => $self->method_name_var,
            -width => $label_width,
            )->pack(
                -side => 'left',
                -expand => 'x',
                );
        
        # Start not found and end not found and method widgets
        $self->add_start_end_method_widgets($frame);
        
        # Transcript remark widget
        $self->add_transcript_remark_widget($frame);
       
        # Widget for changing locus properties
        my $locus_frame = $canvas->toplevel->LabFrame(
            -label => 'Locus',
            -border => 3,
            )->pack(
                -side => 'top',
                -fill => 'x',
                );
        my $be = $self->add_locus_editing_widgets($locus_frame);    
        
        
    } else {
        # SubSeq with an immutable method - wont display entry widgets for updating things
        
        # Only select current text - no focus
        $canvas->Tk::bind('<Button-1>', sub{
            $self->left_button_handler;
            if ($self->count_selected) {
                $canvas->SelectionOwn( -command => $deselect_sub );
            }
        });
    }
    
    $file_menu->add('separator');
    
    # To close window
    $file_menu->add('command',
        -label          => 'Close',
        -command        => $window_close,
        -accelerator    => 'Ctrl+W',
        -underline      => 1,
        );
    
    
    # For extending selection
    $canvas->Tk::bind('<Shift-Button-1>', sub{
        $self->shift_left_button_handler;
        if ($self->count_selected) {
            $canvas->SelectionOwn( -command => $deselect_sub )
        }
    });
    
    $canvas->Tk::bind('<Destroy>', sub{ $self = undef });
    
    $top->update;
    $self->fix_window_min_max_sizes;
}



sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub SubSeq {
    my( $self, $sub ) = @_;
    
    if ($sub) {
        my $expected = 'Hum::Ace::SubSeq';
        unless ($sub->isa($expected)) {
            confess "Expected a '$expected', but got a '$sub'";
        }
        $self->{'_SubSeq'} = $sub;
        $self->canvas->toplevel->configure(-title => $sub->name);
    }
    return $self->{'_SubSeq'};
}

sub xace_seq_chooser {
    my( $self, $chooser ) = @_;
    
    if ($chooser) {
        $self->{'_xace_seq_chooser'} = $chooser;
    }
    return $self->{'_xace_seq_chooser'};
}

sub add_subseq_exons {
    my( $self, $subseq ) = @_;
    
    my $expected = 'Hum::Ace::SubSeq';
    unless ($subseq->isa($expected)) {
        warn "Unexpected object '$subseq', expected a '$expected'";
    }
    
    my $strand = $subseq->strand;
    foreach my $ex ($subseq->get_all_Exons_in_transcript_order) {
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
        my( $self, $length, $strand ) = @_;
        
        if (my $pp = $self->{$pp_field}) {
            my @del = splice(@$pp, -1 * $length, $length);
            if (@del != $length) {
                confess "only got ", scalar(@del), " elements, not '$length'";
            }
            my $canvas = $self->canvas;
            foreach my $exon_id (map $_->[2], @del) {
                $canvas->delete($exon_id);
            }
            $self->decrement_exon_counter($length);
        } else {
            confess "No pairs to trim";
        }
        $self->set_tk_strand($strand) if $strand;
        $self->position_mobile_elements;
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

sub set_position_pair_text {
    my( $self, $pp, $text_pair, $strand ) = @_;
    
    $strand ||= $self->strand_from_tk;

    my $canvas = $self->canvas;
    my @txt = @$text_pair;
    @txt = reverse @txt if $strand == -1;
    foreach my $i (0,1) {
        my $obj = $pp->[$i];
        my $pos = $txt[$i] || $self->empty_string;
        $canvas->itemconfigure($obj, -text => $pos);
    }
}

sub set_all_position_pair_text {
    my( $self, @coord ) = @_;

    my @pp_list = $self->position_pairs;
    if (@pp_list != @coord) {
        confess "position pair number '", scalar(@pp_list),
            "' doesn't match number of coordinates '", scalar(@coord), "'";
    }
    for (my $i = 0; $i < @pp_list; $i++) {
        $self->set_position_pair_text($pp_list[$i], $coord[$i]);
    }
}

sub sort_all_coordinates {
    my( $self ) = @_;
    
    $self->sort_position_pairs;
    $self->sort_translation_region;
}

sub sort_position_pairs {
    my( $self ) = @_;

    my %was_selected = map {$_, 1} $self->get_all_selected_text;
    $self->deselect_all;

    my $empty  = $self->empty_string;
    my $canvas = $self->canvas;
    my $strand = $self->strand_from_tk;

    my( @sort );
    if ($strand == 1) {
        @sort = sort {$a->[0] <=> $b->[0] || $a->[1] <=> $b->[1]}
            $self->all_position_pair_text;
    } else {
        @sort = sort {$b->[0] <=> $a->[0] || $b->[1] <=> $a->[1]}
            $self->all_position_pair_text;
    }

    my $n = 0;
    my( @select );
    foreach my $pp ($self->position_pairs) {
        my @num = @{$sort[$n]};
        @num = reverse @num if $strand == -1;
        foreach my $i (0,1) {
            my $pos = $num[$i] || $empty;
            my $obj = $pp->[$i];
            push(@select, $obj) if $was_selected{$pos};
            $canvas->itemconfigure($obj, -text => $pos);
        }
        $n++;
    }
    $self->highlight(@select) if @select;
}

sub sort_translation_region {
    my( $self ) = @_;

    my @region  = $self->translation_region_from_tk or return;
    my $strand  = $self->strand_from_tk;
    if ($strand == 1) {
        $self->tk_t_start($region[0]);
        $self->tk_t_end  ($region[1]);
    } else {
        $self->tk_t_start($region[1]);
        $self->tk_t_end  ($region[0]);
    }
}

sub merge_position_pairs {
    my( $self ) = @_;
    
    $self->deselect_all;
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
    
    my @pairs  = $self->position_pairs;
    for (my $i = 0; $i < @pos; $i++) {
        $self->set_position_pair_text($pairs[$i], $pos[$i]);
    }
    if (my $over = @pairs - @pos) {
        $self->trim_position_pairs($over);
        $self->fix_window_min_max_sizes;
    }
}

sub delete_selected_exons {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my @selected = $self->list_selected;
    $self->deselect_all;
    my( %del_exon );
    foreach my $obj (@selected) {
        my ($exon_id) = grep /^exon_id/, $canvas->gettags($obj);
        if ($exon_id) {
            $del_exon{$exon_id}++;
        }
    }

    my $strand = 0;
    my @text    = $self->all_position_pair_text;
    my @pp_list = $self->position_pairs;
    my $trim = 0;
    my( @keep );
    for (my $i = 0; $i < @pp_list; $i++) {
        my $exon_id = $pp_list[$i][2];
        my $count = $del_exon{$exon_id};
        if ($count and $count == 2) {
            $trim++;
        } else {
            $strand += $self->exon_strand_from_tk($exon_id);
            push(@keep, $text[$i]);
        }
    }
    
    return unless $trim;
    
    $strand = $strand < 0 ? -1 : 1;
    
    $self->trim_position_pairs($trim, $strand);
    $self->set_all_position_pair_text(@keep);
    
    # Put in an empty exon holder if we have deleted them all
    unless ($self->position_pairs) {
        $self->add_exon_holder(undef, undef, 1);
    }
}

sub exon_strand_from_tk {
    my( $self, $exon_id ) = @_;
    
    confess "exon_id not given" unless $exon_id;
    if ($self->canvas->find('withtag', "plus_strand&&$exon_id")) {
        return 1;
    } else {
        return -1;
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

sub draw_subseq {
    my( $self ) = @_;
    
    my $sub = $self->SubSeq;
    $self->add_subseq_exons($sub);
    $self->draw_translation_region($sub);
    $self->evidence_hash($sub->clone_evidence_hash);
}

sub is_mutable {
    my( $self ) = @_;
    
    return $self->SubSeq->is_mutable;
}

sub window_close {
    my( $self ) = @_;
    
    my $xc = $self->xace_seq_chooser;
    
    if ($self->is_mutable && $xc->write_access) {
        my( $sub );
        eval{
            if ($sub = $self->get_SubSeq_if_changed) {
                $sub->validate;
            }
        };
        
        my $name = $self->name;

        if ($@) {
            $self->exception_message($@);
            my $dialog = $self->canvas->toplevel->Dialog(
                -title          => 'Abandon?',
                -bitmap         => 'question',
                -text           => "SubSequence '$name' has errors.\nAbandon changes?",
                -default_button => 'No',
                -buttons        => [qw{ Yes No }],
                );
            my $ans = $dialog->Show;
            return if $ans eq 'No';
        }
        elsif ($sub) {
        
            # Ask the user if changes should be saved
            my $dialog = $self->canvas->toplevel->Dialog(
                -title          => 'Save changes?',
                -bitmap         => 'question',
                -text           => "Save changes to SubSequence '$name' ?",
                -default_button => 'Yes',
                -buttons        => [qw{ Yes No Cancel }],
                );
            my $ans = $dialog->Show;

            if ($ans eq 'Cancel') {
                return; # Abandon window close
            }
            elsif ($ans eq 'Yes') {
                $self->xace_save($sub) or return;
            }
        }
    }
    $self->delete_chooser_window_ref;
    $self->canvas->toplevel->destroy;
   
    return 1;
}

sub show_subseq {
    my( $self ) = @_;

    
    my $xr = $self->xace_seq_chooser->xace_remote  || $self->xace_seq_chooser->open_xace_dialogue;
    if ($xr) {
        my $sub = $self->SubSeq;
        unless ($sub->is_archival) {
            $self->message("Not yet saved");
            return;
        }
        
        if ($sub->get_all_Exons) {
            $xr->show_SubSeq($sub);
        } else {
            $self->message("Can't show an empty SubSequence");
        }
    } else {
        $self->message("No xace attached");
    }
};

sub show_peptide {
    my( $self ) = @_;

    my $peptext = $self->{'_pep_peptext'};

    my( $sub );
    if ($self->is_mutable) {
        $sub = $self->new_SubSeq_from_tk;
        unless ($sub->GeneMethod->transcript_type eq 'coding') {
            if ($peptext) {
                $peptext->toplevel->withdraw;
            }
            $self->message("non-coding method");
            return;
        }
    }

    unless ($peptext) {
        my $master = $self->canvas->toplevel;
        my $top = $master->Toplevel;
        $top->transient($master);
        my $font = $self->font;
        my $size = $self->font_size;
        
        $self->{'_pep_peptext'} = $peptext = $top->ROText(
            -font           => [$font, $size, 'normal'],
            #-justify        => 'left',
            -padx                   => 6,
            -pady                   => 6,
            -relief                 => 'groove',
            -background             => 'white',
            -border                 => 2,
            -selectbackground       => 'gold',
            #-exportselection => 1,
            )->pack(
                -expand => 1,
                -fill   => 'both',
                );
        
        # Red for stop codons
        $peptext->tagConfigure('redstop',
            -background => '#ef0000',
            -foreground => 'white',
            );
        
        # Blue for "X", the unknown amino acid
        $peptext->tagConfigure('blueunk',
            -background => '#0000ef',
            -foreground => 'white',
            );
        # Gold for methionine codons
        $peptext->tagConfigure('goldmeth' ,
            -background => '#ffd700',
            -foreground => 'black',
        );
        $peptext->tagBind('goldmeth', '<Button-1>',
            sub{ $self->trim_cds_coord_to_current_methionine; }
            );
        $peptext->tagBind('goldmeth', '<Enter>',
            sub{ $peptext->configure(-cursor => 'arrow'); }
            );
        $peptext->tagBind('goldmeth', '<Leave>',
            sub{ $peptext->configure(-cursor => 'xterm'); }
            );
        $peptext->tagBind('goldmeth' , '<Button-3>' , 
            sub{ $self->check_kozak} 
            ); 
        
        # Frame for buttons
        my $frame = $top->Frame(
            -border => 6,
            )->pack(
                -side   => 'bottom',
                -fill   => 'x',
                );
        
        my $trim_command = sub{
            $self->trim_cds_coord_to_first_stop;
            $self->show_peptide;
            };
        $frame->Button(
            -text       => 'Trim',
            -underline  => 0,
            -command    => $trim_command ,
            )->pack(-side => 'left');
        $top->bind('<Control-t>',   $trim_command);
        $top->bind('<Control-T>',   $trim_command);
        $top->bind('<Return>',      $trim_command);
        $top->bind('<KP_Enter>',    $trim_command);

        # Close only unmaps it from the display
        my $close_command = sub{ $top->withdraw };
        
        my $exit = $frame->Button(
            -text => 'Close',
            -command => $close_command ,
            )->pack(-side => 'right');
        $top->bind(    '<Control-w>',      $close_command);
        $top->bind(    '<Control-W>',      $close_command);
        $top->bind(    '<Escape>',         $close_command);
        
        
        # Closing with window manager only unmaps window
        $top->protocol('WM_DELETE_WINDOW', $close_command);

        $peptext->bind('<Destroy>', sub{ $self = undef });
    }

    # Empty the text widget    
    $peptext->delete('1.0', 'end');

    eval{ $sub->validate; };
    if ($@) {
        $self->exception_message($@, 'Invalid transcript');
        $peptext->insert('end', "TRANSLATION ERROR");
    } else {
        # Put the new translation into the Text widget
       
        my $pep = $self->translator->translate($sub->translatable_Sequence);
        $peptext->insert('end', sprintf(">%s\n", $pep->name));

        my $line_length = 60;
        my $str = $pep->sequence_string;
        my $map = $sub->codon_start_map;
        my %style = (
            '*' => 'redstop',
            'X' => 'blueunk',
            'M' => 'goldmeth',
            );
        my $pep_genomic = $self->{'_peptext_index_to_genomic_position'} = {};
        for (my $i = 0; $i < length($str); $i++) {
            my $char = substr($str, $i, 1);
            my $tag = $style{$char};
            $peptext->insert('end', $char, $tag);
            
            if ($char eq 'M') {
                my $index = $peptext->index('insert - 1 chars');
                #printf STDERR "$index  $map->[$i]\n";
                $pep_genomic->{$index} = $map->[$i];
            }
            
            unless (($i + 1) % $line_length) {
                $peptext->insert('end', "\n");
            }
        }
    }
    
    
    # Size widget to fit
    my ($lines) = $peptext->index('end') =~ /(\d+)\./;    
    $lines--;
    $peptext->configure(
        -width  => 60,
        -height => $lines,
        );
    
    # Set the window title, and make it visible
    my $win = $peptext->toplevel;
    $win->configure( -title => $sub->name . " translation" );
    $win->deiconify;
    $win->raise;
}
 
sub evidence_hash {
    my( $self, $evidence_hash ) = @_;
    
    if ($evidence_hash) {
        $self->{'_evidence_hash'} = $evidence_hash;
    }
    return $self->{'_evidence_hash'};
}

sub select_evidence {
    my( $self ) = @_;
    
    my $evi_coll = $self->xace_seq_chooser->EviCollection
        or die "No EviCollection attatched to XaceSeqChooser";
    ### Need to close EviDisplay here if there is one already open
    my $otter_transcript = $self->otter_Transcript_from_tk;
    my $title = "Evidence: ". $otter_transcript->transcript_info->name;
    my $evi_disp = Evi::EviDisplay->new(
        $self->canvas->toplevel,
        $title,
        $evi_coll,
        $otter_transcript,
        );
    $evi_disp->ExonCanvas($self);
}

sub save_OtterTranscript_evidence {
    my( $self, $transcript ) = @_;
    
    my $info = $transcript->transcript_info;
    my $evi_hash = {};
    foreach my $evi (@{$info->get_all_Evidence}) {
        my $type = $evi->type;
        my $name = $evi->name;
        my $evi_list = $evi_hash->{$type} ||= [];
        push @$evi_list, $name;
    }
    $self->evidence_hash($evi_hash);
}

sub trim_cds_coord_to_current_methionine {
    my( $self ) = @_;
    
    my $peptext = $self->{'_pep_peptext'} or return;
    my $index = $peptext->index('current');
    my $new = $self->{'_peptext_index_to_genomic_position'}{$index} or return;

    $self->deselect_all;
    my $original = $self->tk_t_start;
    $self->tk_t_start($new);

    # Highlight the translation end if we have changed it
    $self->highlight('t_start') if $new != $original;
}



sub check_kozak{
    my ($self ) = @_ ;
    
    my $kozak_window = $self->{'_kozak_window'} ;
    # create a new window if none available
    unless (defined $kozak_window){
        my $master = $self->canvas->toplevel;
        $kozak_window = $master->Toplevel(-title => 'Kozak Checker');
        $kozak_window->transient($master);
        
        my $font = $self->font;
        my $size = $self->font_size;

        $kozak_window->Label(
                -font           => [$font, $size, 'normal'],
                -text           => "5'\n3'" ,    
                -padx                   => 6,
                -pady                   => 6, 
                )->pack(-side   => 'left'); 
        
        my $kozak_txt = $kozak_window->ROText(
                -font           => [$font, $size, 'normal'],
                #-justify        => 'left',
                -padx                   => 6,
                -pady                   => 6,
                -relief                 => 'groove',
                -background             => 'white',
                -border                 => 2,
                -selectbackground       => 'gold',
                #-exportselection => 1,
                
                -width                  => 10 ,
                -height                 => 2 ,
                )->pack(-side   => 'left' , 
                        -expand => 1      ,
                        -fill   => 'both' ,
                        );
                        
                     
        $kozak_window->Label(
                -font           => [$font, $size, 'normal'],
                -text           => "3'\n5'" ,    
                -padx                   => 6,
                -pady                   => 6, 
                )->pack(-side   => 'left');                         
        
        my $close_kozak = sub { $kozak_window->withdraw } ;
        my $kozak_butt = $kozak_window->Button( -text       => 'close' ,
                                            -command    => $close_kozak ,
                                            )->pack(-side => 'left')  ;
        $self->{'_kozak_txt'} = $kozak_txt ;
        $self->{'_kozak_window'} = $kozak_window;
        
    }
    
    my $kozak_txt = $self->{'_kozak_txt'} ;
    
    ### get index of selected methionine
    my $peptext = $self->{'_pep_peptext'} or return;
    my $pep_index = $peptext->index('current');  
    my $seq_index = $self->{'_peptext_index_to_genomic_position'}{$pep_index} or return;

    my $subseq = $self->SubSeq ;    
    my $clone_seq = $subseq->clone_Sequence();
    my $sequence_string = $clone_seq->sequence_string;
    my $strand = $subseq->strand;
    
    my $k_start ;

    if ($strand == 1){
        $k_start = ($seq_index  - 7 ) ;
    }else{    
        $k_start = ($seq_index  - 4 ) ;
    }
  
    my $kozak ;
    if ( $k_start >= 0 ){
        $kozak = substr($sequence_string ,  $k_start  , 10 ) ;  
    }
    else{
        # if subseq  goes off start , this will pad it with '*'s to make it 10 chars long      
        $kozak =  "*" x ( $k_start * -1) . substr($sequence_string ,  0  , 10 + $k_start ) ;    
    }
    
    my $rev_kozak = $kozak ;
    $rev_kozak =~ tr{acgtrymkswhbvdnACGTRYMKSWHBVDN}
                    {tgcayrkmswdvbhnTGCAYRKMSWDVBHN}; 
    $kozak  =~ s/t/u/g  ;
    $rev_kozak =~ s/t/u/g  ;
    
    
    $kozak_window->resizable( 1 , 1)  ;  
    $kozak_txt->delete( '1.0' , 'end')  ;
    $kozak_window->resizable(0 , 0)  ;
        
    # higlight parts of sequence that match 
    # green for matches codons
    $kozak_txt->tagConfigure('match',
            -background => '#AAFF66',
            );

    # from an email from [cas]
    # shows how the template matches various recognised Kozak consensi.
    ############################  perfect, strong, adequate, chr22 version
    my @template_kozak = ('(a|g)',   # G   
                          'c',       # C
                          'c',       # C
                          'a',       # A    A   G   G  Y     G
                          'c',       # C    n   n   n  n     n
                          'c',       # C    n   n   n  n     n
                          'a',       # A    A   A   A  A     A
                          'u',       # T    T   T   T  T     T
                          'g',       # G    G   G   G  G     G
                          'g');      # G    n   G   Y  G     A
    
    ## for some reason (tk bug?) tk would not display tags added to the second line when using the index system - hence two loops rather than one
    for( my $i = 0 ;  $i <= ( length($kozak) - 1) ; $i++ ){
        my $pos_char = substr( $kozak , $i , 1) ;
        my $template = $template_kozak[$i] ;       
        if ($pos_char  =~ /$template/ && $strand == 1){    
            $kozak_txt->insert('end' , "$pos_char" , 'match');
        }else{
            $kozak_txt->insert('end' , "$pos_char" );
        } 
    }
    
    for (my $i = 0 ;  $i <= ( length($rev_kozak) - 1) ; $i++ ){
        my $template = $template_kozak[9 - $i] ;
        my $neg_char = substr( $rev_kozak ,  $i   , 1) ;    
        if ($neg_char  =~ /$template/  && $strand == -1){   
            $kozak_txt->insert('end' , "$neg_char" , "match");
        }else{
            $kozak_txt->insert('end' , "$neg_char");
        }
    }
            
    $kozak_window->deiconify;
    $kozak_window->raise ; 
              
}

sub trim_cds_coord_to_first_stop {
    my( $self ) = @_;

    unless ($self->get_GeneMethod_from_tk->transcript_type eq 'coding') {
        $self->message('non-coding method');
        return;
    }
    
    $self->deselect_all;
    my $sub = $self->new_SubSeq_from_tk;
    my $strand = $sub->strand;
    my $original = $self->tk_t_end;
    if ($strand == 1) {
        $self->tk_t_end($sub->end);
    } else {
        $self->tk_t_end($sub->start);
    }
    
    # Translate the subsequence
    $sub = $self->new_SubSeq_from_tk;
    my $pep = $self->translator->translate($sub->translatable_Sequence);
    my $pep_str = $pep->sequence_string;
    
    # Find the first stop character
    my $stop_pos = index($pep_str, '*', 0);
    if ($stop_pos == -1) {
        $self->message("No stop codon found");
        return;
    }
    
    # Convert from peptide to CDS coordinates
    $stop_pos++;
    my $cds_coord = ($stop_pos * 3) + $sub->start_phase - 1;
    
    # Get a list of exons in translation order
    my @exons = $sub->get_all_CDS_Exons;
    if ($strand == -1) {
        @exons = reverse @exons;
    }
    
    # Find the exon that contains the stop, and use its
    # coordinates to map back to genomic coordinates
    my $pos = 0;
    foreach my $ex (@exons) {
        my $exon_end = $pos + $ex->length;
        if ($cds_coord <= $exon_end) {
            my $exon_offset = $cds_coord - $pos;
            my( $new );
            if ($strand == 1) {
                $new = $ex->start + $exon_offset - 1;
            } else {
                $new = $ex->end + 1 - $exon_offset;
            }
            $self->tk_t_end($new);

            # Highlight the translation end if we have changed it
            $self->highlight('t_end') if $new != $original;
            return 1;
        }
        $pos = $exon_end;
    }
    $self->message("Failed to map coordinate");
}

sub translator {
    my( $self ) = @_;
    
    # Cache a copy of a translator object
    my( $tlr );
    unless ($tlr = $self->{'_translator'}) {
        $self->{'_translator'} = $tlr = Hum::Translator->new;
    }
    return $tlr;
}

sub add_locus_editing_widgets {
    my( $self, $widget ) = @_;
    
    # Get the Locus name
    my( $locus_name, $locus_description, $locus_remark );
    if (my $locus = $self->SubSeq->Locus) {
        $locus_name        = $locus->name;
        $locus_description = $locus->description;
        if (my @remarks = $locus->list_remarks) {
            $locus_remark = join '; ', @remarks;
        }
    }
    $locus_name        ||= '';
    $locus_remark      ||= '';
    $locus_description ||= '';
    $self->{'_locus_name_variable'}        = \$locus_name;
    
    my $be = $widget->ComboBox(
        #-listwidth  => 18,
        -listheight => 10,
        -label      => 'Name: ',
        -width      => 18,
        -variable   => $self->{'_locus_name_variable'},

        -exportselection    => 1,
        -background         => 'white',
        -selectbackground   => 'gold',
        -font               => [$self->font, $self->font_size, 'normal'],
        )->pack(-side => 'top');
    #$be->bind('<Leave>', sub{ print STDERR "Variable now: ", ${$self->{'_locus_name_variable'}}, "\n"; });


    $be->configure(
        -listcmd => sub{
            my @names = $self->xace_seq_chooser->list_Locus_names;
            $be->configure(
                -choices   => [@names],
                #-listwidth => scalar @names,
                );}
        );

    my $de = $self->make_labelled_entry_widget($widget, 'Description', $locus_description, 30, -anchor => 'e');
    my $re = $self->make_labelled_entry_widget($widget, 'Remark',      $locus_remark,      30, -anchor => 'se');

    $self->locus_description_Entry($de);
    $self->locus_remark_Entry($re);

    # Avoid memory cycle created by ref to $self in above closure
    $be->Tk::bind('<Destroy>', sub{ $self = undef });

    return $be;
}

sub update_Locus_tk_fields {
    my( $self, $locus ) = @_;
    
    # Can this be done for the name too?
    
    my $de = $self->locus_description_Entry;
    $de->delete(0, 'end');
    if (my $desc = $locus->description) {
        $de->insert(0, $desc);
    }

    my $re = $self->locus_remark_Entry;
    $re->delete(0, 'end');
    if (my @remark = $locus->list_remarks) {
        $re->insert(0, join('; ', @remark));
    }
}

sub get_Locus_from_tk {
    my( $self ) = @_;
    
    my $name = ${$self->{'_locus_name_variable'}} or return;
    my $desc   = $self->get_locus_description;
    my $remark = $self->get_locus_remark;
    
    #warn "name '$name'\ndesc '$desc'\nremark '$remark'\n";
    
    if ($name =~ /\s/) {
        $self->message("Error: whitespace in Locus name '$name'");
        return;
    }
    
    my $locus = Hum::Ace::Locus->new;
    $locus->name($name);
    $locus->description($desc)   if $desc;
    $locus->set_remarks($remark) if $remark;
    return $locus;
}

sub add_transcript_remark_widget {
    my( $self, $widget ) = @_;
    
    $self->transcript_remark_Entry(
        $self->make_labelled_entry_widget(
            $widget, 'Remark',
            join('; ', $self->SubSeq->list_remarks),
            30, -anchor => 'se')
        );
}

sub add_subseq_rename_widget {
    my( $self, $widget ) = @_;
    
    $self->subseq_name_Entry(
        $self->make_labelled_entry_widget($widget, 'Name', $self->SubSeq->name, 22, -side => 'top')
        );
}

sub make_labelled_entry_widget {
    my( $self, $widget, $name, $value, $size, @pack ) = @_;
    
    @pack = (-side => 'left') unless @pack;
    
    my $frame = $widget->Frame(
        -border => 3,
        )->pack(@pack);
    
    my $entry_label = $frame->Label(
        -text   => "$name:",
        -anchor => 's',
        -padx   => 6,
        );
    $entry_label->pack(-side => 'left');

    my $entry = $frame->Entry(
        -width              => $size,
        -exportselection    => 1,
        );
    $entry->pack(-side => 'left');
    $entry->insert(0, $value) if $value;
    return $entry;
}

sub add_start_end_method_widgets {
    my( $self, $widget ) = @_;
    
    my $top = $widget->toplevel;
    my $frame = $widget->Frame(
        -border => 6,
        )->pack(
            -side   => 'top',
            -expand => 0,
            );

    $frame->Label(
        -text   => 'Start:',
        -padx   => 6,
        )->pack(-side => 'left');

    # Menu
    my( $snf );
    my $om = $frame->Optionmenu(
        -variable   => \$snf,
        -options    => [
                ['Found'          => 0],
                ['Not found - 1'  => 1],
                ['Not found - 2'  => 2],
                ['Not found - 3'  => 3],
            ],
        -takefocus  => 0,   # Doesn't work
        -command    => sub{ $top->focus },  # Need this
        )->pack(
            -side => 'left',
            );
    $snf = $self->SubSeq->start_not_found;
    $om->menu->invoke($snf);
    #warn "snf = $snf";

    # Pad between Start and End not found widgets
    $frame->Frame(
        -width  => 10,
        )->pack(-side => 'left');

    $self->{'_start_not_found_variable'} = \$snf;

    $frame->Label(
        -text   => 'End:',
        -padx   => 6,
        )->pack(-side => 'left');

    # Menu
    my( $enf );
    $om = $frame->Optionmenu(
        -variable   => \$enf,
        -options    => [
                ['Found'        => 0],
                ['Not found'    => 1],
            ],
        -takefocus  => 0,   # Doesn't work
        -command    => sub{ $top->focus },  # Need this
        )->pack( -side => 'top' );
    $enf = $self->SubSeq->end_not_found;
    $om->menu->invoke($enf);
    #warn "enf = $enf";

    $self->{'_end_not_found_variable'} = \$enf;
}

sub start_not_found_from_tk {
    my( $self ) = @_;
    
    return ${$self->{'_start_not_found_variable'}} || 0;
}

#sub continued_from_from_tk {
#    my( $self ) = @_;
#    
#    my $txt = $self->{'_continued_from_Entry'}->get;
#    $txt =~ s/\s+//g;
#    return $txt || '';
#}
#
#sub continues_as_from_tk {
#    my( $self ) = @_;
#    
#    my $txt = $self->{'_continues_as_Entry'}->get;
#    $txt =~ s/\s+//g;
#    return $txt || '';
#}

sub end_not_found_from_tk {
    my( $self ) = @_;
    
    return ${$self->{'_end_not_found_variable'}} || 0;
}

sub subseq_name_Entry {
    my( $self, $entry ) = @_;
    
    if ($entry) {
        $self->{'_subseq_name_entry'} = $entry;
    }
    return $self->{'_subseq_name_entry'};
}

sub transcript_remark_Entry {
    my( $self, $transcript_remark_Entry ) = @_;
    
    if ($transcript_remark_Entry) {
        $self->{'_transcript_remark_Entry'} = $transcript_remark_Entry;
    }
    return $self->{'_transcript_remark_Entry'};
}

sub get_transcript_remark {
    my( $self ) = @_;
    
    my $remark = $self->transcript_remark_Entry->get;
    $remark =~ s/(^\s+|\s+$)//g;
    if ($remark) {
        return $remark;
    } else {
        return;
    }
}

sub locus_remark_Entry {
    my( $self, $locus_remark_Entry ) = @_;
    
    if ($locus_remark_Entry) {
        $self->{'_locus_remark_Entry'} = $locus_remark_Entry;
    }
    return $self->{'_locus_remark_Entry'};
}

sub get_locus_remark {
    my( $self ) = @_;
    
    my $remark = $self->locus_remark_Entry->get;
    $remark =~ s/(^\s+|\s+$)//g;
    if ($remark) {
        return $remark;
    } else {
        return;
    }
}

sub locus_description_Entry {
    my( $self, $locus_description_Entry ) = @_;
    
    if ($locus_description_Entry) {
        $self->{'_locus_description_Entry'} = $locus_description_Entry;
    }
    return $self->{'_locus_description_Entry'};
}

sub get_locus_description {
    my( $self ) = @_;
    
    my $desc = $self->locus_description_Entry->get;
    $desc =~ s/(^\s+|\s+$)//g;
    if ($desc) {
        return $desc;
    } else {
        return;
    }
}

sub get_subseq_name {
    my( $self ) = @_;
    
    my $name = $self->subseq_name_Entry->get;
    $name =~ s/\s+//g;
    return $name || 'NO-NAME';
}

sub set_subseq_name {
    my( $self, $new ) = @_;
    
    my $entry = $self->subseq_name_Entry;
    $entry->delete(0, 'end');
    $entry->insert(0, $new);
}

sub method_name_var {
    my( $self, $var_ref ) = @_;
    
    if ($var_ref) {
        $self->{'_method_name_var'} = $var_ref;
    }
    return $self->{'_method_name_var'};
}

sub get_GeneMethod_from_tk {
    my( $self ) = @_;
    
    my $meth_name = ${$self->method_name_var};
    return $self->xace_seq_chooser->get_GeneMethod($meth_name);
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
    my( $self ) = @_ ;
    
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
    my ($obj)  = $canvas->find('withtag', 'current')  or return;
    if (grep /translation_region|exon_pos/, $canvas->gettags($obj) ) {
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

    my ($obj) = $canvas->find('withtag', 'current')  or return;
    my $type  = $canvas->type($obj)                  or return;
    my @tags  = $canvas->gettags($obj);

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
    my ($obj) = $canvas->find('withtag', 'current') or return;
    my %tags = map {$_, 1} $canvas->gettags($obj);
    if ($tags{'plus_strand'}) {
        $self->set_tk_strand(-1);
    }
    elsif ($tags{'minus_strand'}) {
        $self->set_tk_strand(1);
    }
}

sub set_tk_strand {
    my( $self, $strand ) = @_;
    
    my( $del_tag, $draw_method );
    if ($strand == 1) {
        $del_tag = 'minus_strand';
        $draw_method = 'draw_plus';
    } else {
        $del_tag = 'plus_strand';
        $draw_method = 'draw_minus';
    }
    
    my $canvas = $self->canvas;
    foreach my $obj ($canvas->find('withtag', $del_tag)) {
        my @tags = grep $_ ne $del_tag, $canvas->gettags($obj);
        $canvas->delete($obj);
        my ($i) = map /exon_id-(\d+)/, @tags;
        #warn "Drawing strand indicator for exon $i\n";
        my( $size, $half, $pad,
            $x1, $y1, $x2, $y2 ) = $self->exon_holder_coords($i - 1);
        $self->$draw_method($x1 + $half, $y1, $size, @tags);
    }
    
    $self->sort_all_coordinates;
}

sub toggle_tk_strand {
    my( $self ) = @_;
    
    if ($self->strand_from_tk == 1) {
        $self->set_tk_strand(-1);
    } else {
        $self->set_tk_strand(1);
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
    my $clip = '';
    if (@text == 1) {
        $clip = $text[0];
    } else {
        for (my $i = 0; $i < @text; $i += 2) {
            my($start, $end) = @text[$i, $i + 1];
            $end ||= $self->empty_string;
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
        
    my $sub = $self->new_SubSeq_from_tk;
    my $text = $sub->ace_string;
    if (length($text) > $max_bytes) {
        die "text too big";
    }
    warn $text;
    return $text;
}
    
sub middle_button_paste {
    my( $self ) = @_;

    my $canvas = $self->canvas;
    my @ints = $self->integers_from_clipboard;
    return unless @ints;
    
    $self->deselect_all;
    if (my ($obj)  = $canvas->find('withtag', 'current')) {
        my $type = $canvas->type($obj) or return;
        if ($type eq 'text') {
            $canvas->itemconfigure($obj, 
                -text   => $ints[0],
                );
            $self->highlight($obj);
        }
        ### Could set coordinates with middle button on strand indicator
    } else {
        for (my $i = 0; $i < @ints; $i += 2) {
            $self->add_coordinate_pair(@ints[$i, $i + 1]);
        }
        #$self->set_scroll_region_and_maxsize;
        $self->fix_window_min_max_sizes;
    }
}

sub next_exon_holder_coords {
    my( $self ) = @_;
    
    my $i = $self->next_position_pair_index;
    return $self->exon_holder_coords($i);
}

sub exon_holder_coords {
    my( $self, $i ) = @_;
    
    my( $size, $half, $pad, $text_len, @bbox ) = $self->_coord_matrix;
    my $y_offset = $i * ($size + (2 * $pad));
    $bbox[1] += $y_offset;
    $bbox[3] += $y_offset;
    return( $size, $half, $pad, @bbox );
}

sub _coord_matrix {
    my( $self ) = @_;
    
    #my $old = $self->font_size;
    #$self->font_size($old * 1.2);
    
    my( $m );
    unless ($m = $self->{'_coord_matrix'}) {
        my $uw      = $self->font_unit_width;
        my $size    = $self->font_size;
        my $max_chars = 8;  # For coordinates up to 99_999_999
        my $text_len = $max_chars * $uw;
        my $half = int($size / 2);
        my $pad  = int($size / 6);
        
        my $x1 = $half + $size + (2 * $text_len);
        my $y1 = $half;
        $m = [
            $size, $half, $pad, $text_len,
            $x1,               $y1,
            $x1 + ($size * 2), $y1 + $size,
            ];
        $self->{'_coord_matrix'} = $m;
        
        # Create rectangle to pad canvas to max number width
        my $canvas = $self->canvas;
        my $max_width = 4 * ($size + $text_len);
        #warn "max_width = $max_width\n";
        $canvas->createRectangle(
            $half, $half,
            $half + $max_width, $half + $size,
            -fill       => undef,
            -outline    => undef,
            -tags       => ['max_width_rectangle'],
            );
    }
    
    #$self->font_size($old);
    
    return @$m;
}

sub add_exon_holder {
    my( $self, $start, $end, $strand ) = @_;
    
    $start ||= $self->empty_string;
    $end   ||= $self->empty_string;
    
    my $arrow = ($strand == 1) ? 'last' : 'first';
    if ($strand == -1) {
        ($start, $end) = ($end, $start);
    }
    
    my $canvas  = $self->canvas;
    my $font    = $self->font;
    my $exon_id = 'exon_id-'. $self->next_exon_number;
    my( $size, $half, $pad,
        $x1, $y1, $x2, $y2 ) = $self->next_exon_holder_coords;
    my $arrow_size = $half - $pad;
    
    my $start_text = $canvas->createText(
        $x1, $y1 + $half,
        -anchor     => 'e',
        -text       => $start,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id, 'exon_start', 'exon_pos'],
        );
    
    if ($strand == 1) {
        $self->draw_plus ($x1 + $half, $y1, $size, $exon_id, 'exon_furniture');
    } else {
        $self->draw_minus($x1 + $half, $y1, $size, $exon_id, 'exon_furniture');
    }
    
    my $end_text = $canvas->createText(
        $x2, $y1 + $half,
        -anchor     => 'w',
        -text       => $end,
        -font       => [$font, $size, 'normal'],
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
    
    $self->position_mobile_elements;
    
    # Return how big we were
    return $size + $pad;
}

sub position_mobile_elements {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    return unless $canvas->find('withtag', 'mobile');
    my $size = $self->font_size;
    my $pad  = int($size / 2);

    my $mobile_top   = ($canvas->bbox( 'mobile'))[1];
    my $fixed_bottom = ($canvas->bbox('!mobile'))[3] + $pad;
    
    $canvas->move('mobile', 0, $fixed_bottom - $mobile_top);
}

sub draw_plus {
    my( $self, $x, $y, $size, @tags ) = @_;
    
    my $third = $size / 3;
    
    $self->canvas->createPolygon(
        $x +     $third,  $y             ,
        $x + 2 * $third,  $y             ,
        $x + 2 * $third,  $y +     $third,
        $x + $size     ,  $y +     $third,
        $x + $size     ,  $y + 2 * $third,
        $x + 2 * $third,  $y + 2 * $third,
        $x + 2 * $third,  $y + $size,
        $x +     $third,  $y + $size,
        $x +     $third,  $y + 2 * $third,
        $x             ,  $y + 2 * $third,
        $x             ,  $y +     $third,
        $x +     $third,  $y +     $third,
        -tags       => [@tags, 'plus_strand'],
        -fill       => 'grey',
        -outline    => 'DimGrey',
        -joinstyle  => 'miter',
        );
}

sub draw_minus {
    my( $self, $x, $y, $size, @tags ) = @_;
    
    my $third = $size / 3;
    
    $self->canvas->createRectangle(
        $x        ,  $y +     $third,
        $x + $size,  $y + 2 * $third,
        -tags       => [@tags, 'minus_strand'],
        -fill       => 'grey',
        -outline    => 'DimGrey',
        );
}

sub strand_from_tk {
    my( $self, $keep_quiet ) = @_;
    
    my $canvas = $self->canvas;
    my @fwd = $canvas->find('withtag', 'plus_strand' );
    my @rev = $canvas->find('withtag', 'minus_strand');
    
    my $guess = 0;
    my( $strand );
    if (@fwd >= @rev) {
        $strand = 1;
        $guess = 1 if @rev;
    } else {
        $strand = -1;
        $guess = 1 if @fwd;
    }
    
    if ($guess) {
        my $dir = $strand == 1 ? 'forward' : 'reverse';
        $self->message("Inconsistent exon directions.  Guessing '$dir'")
            unless $keep_quiet;
    }
    
    return $strand;
}

{
    my $tr_tag = 'translation_region';

    sub draw_translation_region {
        my( $self, $sub ) = @_;

        if ($sub) {
            return unless $sub->translation_region_is_set;
        }

        # Get the translation region from the
        # canvas or the SubSequence
        my( @trans );
        if ($sub) {
            @trans = $sub->translation_region;
        } else {
            @trans = $self->translation_region_from_tk;
            unless (@trans) {
                @trans = $self->SubSeq->translation_region;
            }
        }

        # Delete the existing translation region
        my $canvas = $self->canvas;
        $canvas->delete($tr_tag);

        # Don't draw anything if it isn't coding
        my( $meth, $strand );
        if ($sub) {
            $meth = $sub->GeneMethod;
            $strand = $sub->strand;
        } else {
            $meth = $self->get_GeneMethod_from_tk;#no
            $strand = $self->strand_from_tk;
        }
        return unless $meth->transcript_type eq 'coding'; 

        my $color = $meth->cds_color;
        
        my( $size, $half, $pad, $text_len )
                        = $self->_coord_matrix;
        my $font        = $self->font;
        my $font_size   = $self->font_size;

        if ($strand == -1) {
            @trans = reverse @trans;
        }

        my $t1 = $canvas->createText(
            $half + $text_len, $size,
            -anchor => 'e',
            -text   => $trans[0],
            -font   => [$font, $size, 'bold'],
            -tags   => ['t_start', $tr_tag],
            );
        my $t2 = $canvas->createText(
            (3 * $text_len) + (4 * $size), $size,
            -anchor => 'w',
            -text   => $trans[1],
            -font   => [$font, $size, 'bold'],
            -tags   => ['t_end', $tr_tag],
            );
    }

    sub translation_region_from_tk {
        my( $self ) = @_;

        my $canvas = $self->canvas;
        my( @region );
        foreach my $obj ($canvas->find('withtag', $tr_tag)) {
            push(@region, $canvas->itemcget($obj, 'text'));
        }
        return(sort {$a <=> $b} @region);
    }
}

sub tk_t_start {
    my( $self, $start ) = @_;
    
    my $canvas = $self->canvas;
    my ($t_txt) = $canvas->find('withtag', 't_start')   
        or confess "Can't get t_start";
    if ($start) {
        $canvas->itemconfigure($t_txt, -text => $start);
    } else {
        ($start) = $canvas->itemcget($t_txt, 'text');
    }
    return $start;
}

sub tk_t_end {
    my( $self, $end ) = @_;
    
    my $canvas = $self->canvas;
    my ($t_txt) = $canvas->find('withtag', 't_end')   
        or confess "Can't get t_end";
    if ($end) {
        $canvas->itemconfigure($t_txt, -text => $end);
    } else {
        ($end) = $canvas->itemcget($t_txt, 'text');
    }
    return $end;
}

sub get_SubSeq_if_changed {
    my( $self ) = @_;
    
    my $new = $self->new_SubSeq_from_tk;
    my $old = $self->SubSeq;
    
    # Preserve Otter ids
    $new->take_otter_ids($old);
    if ($old->is_archival and $new->ace_string eq $old->ace_string) {
        return;
    }
    #warn $old->ace_string, $new->ace_string;
    my $new_name = $new->name;
    if ($new_name ne $self->name) {
        if ($self->xace_seq_chooser->get_SubSeq($new_name)) {
            confess "Error: SubSeq '$new_name' already exists\n";
        }
    }
    return $new;
}

sub new_SubSeq_from_tk {
    my( $self ) = @_;

    my $sub = $self->SubSeq->clone;
    $sub->unset_translation_region;
    $sub->unset_Locus;
    $sub->translation_region     ( $self->translation_region_from_tk  );
    $sub->name                   ( $self->get_subseq_name             );
    $sub->replace_all_Exons      ( $self->Exons_from_canvas           );
    $sub->GeneMethod             ( $self->get_GeneMethod_from_tk      );
    $sub->Locus                  ( $self->get_Locus_from_tk           );
    $sub->strand                 ( $self->strand_from_tk              );
    $sub->start_not_found        ( $self->start_not_found_from_tk     );
    $sub->end_not_found          ( $self->end_not_found_from_tk       );
    $sub->evidence_hash          ( $self->evidence_hash               );
    $sub->set_remarks            ( $self->get_transcript_remark       );
    #warn "Start not found ", $self->start_not_found_from_tk, "\n",
    #    "End not found ", $self->end_not_found_from_tk, "\n";
    return $sub;
}

sub otter_Transcript_from_tk {
    my( $self ) = @_;
    
    # Creates mininmal AnnotatedTranscript for use by EviDisplay
    my $tsct = Bio::Otter::AnnotatedTranscript->new;
    my $strand = $self->strand_from_tk;
    foreach my $ex ($self->Exons_from_canvas) {
        my $exon = Bio::EnsEMBL::Exon->new;
        $exon->start($ex->start);
        $exon->end($ex->end);
        $exon->strand($strand);
        $tsct->add_Exon($exon);
    }
    
    my ($tl_start, $tl_end) = $self->translation_region_from_tk;
    if ($tl_start and $tl_end) {
        if ($strand == -1) {
            ($tl_start, $tl_end) = ($tl_end, $tl_start);
        }

        # Add coding region
        my ($start_exon, $start_pos) = Bio::Otter::Converter::exon_pos($tsct, $tl_start);
        my ($end_exon,   $end_pos)   = Bio::Otter::Converter::exon_pos($tsct, $tl_end);
        
        if ($start_exon and $end_exon) {
            my $tsl = Bio::EnsEMBL::Translation->new;
            $tsl->start_Exon($start_exon);
            $tsl->start($start_pos);
            $tsl->end_Exon($end_exon);
            $tsl->end($end_pos);
            
            ### Set exon phases?
            
            
            $tsct->translation($tsl);
        }
    }
    
    my $info = Bio::Otter::TranscriptInfo->new;
    $info->name($self->get_subseq_name);
    my $evi = $self->evidence_hash;
    foreach my $type (sort keys %$evi) {
        foreach my $name (@{$evi->{$type}}) {
            my $supp = Bio::Otter::Evidence->new;
            $supp->type($type);
            $supp->name($name);
            warn qq{Adding evidence: $type "$name"\n};
            $info->add_Evidence($supp);
        }
    }
    $tsct->transcript_info($info);
    
    return $tsct;
}

sub save_if_changed {
    my( $self ) = @_;
    
    eval {
        if (my $sub = $self->get_SubSeq_if_changed) {
            $sub->validate;
            $self->xace_save($sub);
        }
    };
    
    # Make sure the annotators see the messages!
    if ($@) {
        $self->exception_message($@, 'Error saving to acedb');
    }
}

sub xace_save {
    my( $self, $sub ) = @_;
    
    confess "Missing SubSeq argument" unless $sub;

    my $old = $self->SubSeq;
    my $old_name = $old->name;
    my $new_name = $sub->name;
    
    my $clone_name = $sub->clone_Sequence->name;
    if ($clone_name eq $new_name) {
        $self->message("Can't have SubSequence with same name as clone!");
        return;
    }
    
    confess "No Locus" unless $sub->Locus;
    
    my $ace = '';
    
    # Do we need to rename?
    if ($old->is_archival and $new_name ne $old_name) {
        $ace .= $sub->ace_string($old_name);
    } else {
        $ace .= $sub->ace_string;
    }
    
    print STDERR "Sending:\n$ace";
    
    my $xc = $self->xace_seq_chooser;
    my $xr = $xc->xace_remote;
    if ($xr) {
        $xr->load_ace($ace);
        $xr->save;
        $xr->send_command('gif ; seqrecalc');
        $xc->replace_SubSeq($sub, $old_name);
        $self->SubSeq($sub);
        $self->update_Locus_tk_fields($sub->Locus);
        $self->name($new_name);
        $self->evidence_hash($sub->clone_evidence_hash);
        $sub->is_archival(1);
        return 1;
    } else {
        $self->message("No xace attached");
        return 0;
    }
}

sub Exons_from_canvas {
    my( $self ) = @_;
    
    my $done_message = 0;
    my( @exons );
    foreach my $pp ($self->all_position_pair_text) {
        if (grep $_ == 0, @$pp)  {
            confess("Error: Empty coordinate");
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

sub run_dotter {
    my( $self ) = @_;
    
    my( $txt );
    eval{
        $txt = $self->canvas->SelectionGet;
    };
    my( $hit_name );
    if ($txt) {
        # Match fMap "blue box"
        ($hit_name) = $txt =~ /^(?:<?(?:Protein|Sequence)[:>]?)?\"?([^\"\s]+)\"?/;
    }
    unless ($hit_name) {
        $self->message('Cannot see a hit name on the clipboard');
        return;
    }
    
    my( $cdna );
    eval {
        my( $sub );
        if ($self->is_mutable) {
            $sub = $self->new_SubSeq_from_tk;
        } else {
            $sub = $self->SubSeq;
        }
        $sub->validate;
        $cdna = $sub->mRNA_Sequence;
    };
    if ($@) {
        $self->exception_message($@, 'Error fetching mRNA sequence');
        return;
    }
    
    my $dotter = Hum::Ace::DotterLauncher->new;
    $dotter->query_Sequence($cdna);
    $dotter->query_start(1);
    $dotter->query_end($cdna->sequence_length);
    $dotter->subject_name($hit_name);
    
    return $dotter->fork_dotter;
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

sub decrement_exon_counter {
    my( $self, $count ) = @_;
    
    confess "No count given" unless defined $count;
    $self->{'_max_exon_number'} -= $count;
}

sub DESTROY {
    my( $self ) = @_;
    
    my $name = $self->name;
    warn "Destroying ExonCanvas: '$name'\n";
}

sub icon_pixmap {

    return <<'END_OF_PIXMAP';
/* XPM */
static char * exoncanvas_xpm[] = {
/* width height ncolors cpp [x_hot y_hot] */
"48 48 5 1 0 0",
/* colors */
" 	s none	m none	c none",
".	s iconColor2	m white	c white",
"X	s bottomShadowColor	m black	c #636363636363",
"o	s iconColor3	m black	c red",
"O	s iconColor1	m black	c black",
/* pixels */
"   .....................XX                      ",
"   ...o.............o...XX                      ",
"   ...o.............o...XX                      ",
"   ...o.............o...XX                      ",
"   ...o.............o...XX                      ",
"   ...o.............o...XX                      ",
"   ...ooooooooooooooo...XX                      ",
"   ...........oo........XX                      ",
"   .............o.......XX                      ",
"   ..............o......XX                      ",
"   ...............oo....XX                      ",
"   .................o...XX            O         ",
"   ...............oo....XX           O.O        ",
"   ..............o......XX          O...O       ",
"   .............o.......XX         O.....O      ",
"   ...........oo........XX        O.......O     ",
"   ...ooooooooooooooo...XX       O.........O    ",
"   ...o.............o...XX       OOOOO.OOOOO    ",
"   ...o.............o...XX          XO.OXXX     ",
"   ...o.............o...XX         XXO.OXXXX    ",
"   ...o.............o...XX        XXXO.OXXXXX   ",
"   ...o.............o...XX        XXXO.OXXXXX   ",
"   ...o.............o...XX           O.OX       ",
"   ...o.............o...XX           O.OX       ",
"   ...o.............OOOOOOOOOOOOOOOOOO.OX       ",
"   ...ooooooooooooooo..................OX       ",
"   ...ooooooooooooooOOOOOOOOOOOOOOOOOO.OX       ",
"   ...ooooooooooooooo..XXX           O.OX       ",
"   ...ooooooooooooooo...XXXXXXXXXXXXXO.OX       ",
"   ...ooooooooooooooo...XXXXXXXXXXXXXO.OX       ",
"   ...ooooooooooooooo...XXXXXXXXXXXXXO.OX       ",
"   ...ooooooooooooooo...XX           O.OX       ",
"   ...ooooooooooooooo...XX           O.OX       ",
"   ...ooooooooooooooo...XX       OOOOO.OOOOO    ",
"   ...ooooooooooooooo...XX       O.........O    ",
"   ...ooooooooooooooo...XX        O.......O     ",
"   ...ooooooooooooooo...XX         O.....O      ",
"   ...ooooooooooooooo...XX        XXO...OXXXX   ",
"   ...ooooooooooooooo...XX        XXXO.OXXXXX   ",
"   ...ooooooooooooooo...XX         XXXOXXXXX    ",
"   ...ooooooooooooooo...XX          XXXXXXX     ",
"   ...ooooooooooooooo...XX           XXXXX      ",
"   ...........o.........XX            XXX       ",
"   ...........o.........XX             X        ",
"   ............o........XX                      ",
"   ............o........XX                      ",
"    XXXXXXXXXXXXXXXXXXXXXX                      ",
"    XXXXXXXXXXXXXXXXXXXXXX                      "};
END_OF_PIXMAP

}

1;

__END__

=head1 NAME - MenuCanvasWindow::ExonCanvas

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

