## MenuCanvasWindow::GenomicFeatures

package MenuCanvasWindow::GenomicFeatures;

use strict;
use base 'MenuCanvasWindow';
use Tk::NoPasteEntry;

my %signal_info = (
    'polyA_signal' => {
        'order'    => 1,
        'length'   => 6,
        'fullname' => 'PolyA signal',
    },
    'polyA_site' => {
        'order'    => 2,
        'length'   => 2,
        'fullname' => 'PolyA site',
    },
    'pseudo_polyA' => {
        'order'    => 3,
        'length'   => 6,
        'fullname' => 'Pseudo-PolyA signal',
    },
    'TATA_box' => {
        'order'    => 4,
        'length'   => 8,
        'fullname' => 'TATA-box',
    },
    'RSS' => {
        'order'              => 5,
        'fullname'           => 'Recomb. signal seq.',
        'edit_display_label' => 1,
    },
    'EUCOMM' => {
        'order'              => 6,
        'fullname'           => 'EUCOMM exon(s)',
        'edit_score'         => 1,
        'edit_display_label' => 1,
    },
);

sub signal_keys_in_order {
    return sort { $signal_info{$a}{'order'} <=> $signal_info{$b}{'order'} } keys %signal_info;
}

my %strand_name = (
     1 => 'forward',
    -1 => 'reverse',
);

my %arrow = (
     1 => '==>',
    -1 => '<==',
);

my $def_score = 0.5;


# ---------------[EUCOMM]----------------

sub paste_eucomm_data {
    my ($self, $genomic_feature) = @_;
    
    my ($class, $name, $start, $end) = $self->class_object_start_end_from_clipboard;
    if (! $class or $class ne 'Sequence') {
        return;
    }
    
    if ($start > $end) {
        ($start, $end) = ($end, $start);
    }
    
    my $otter = $self->get_otter_ids_of_overlapping_exons($name, $start, $end);
    return unless keys %$otter;

    # Decrease start if start from clipboard is less
    if (my $gf_start = $genomic_feature->{'start'}) {
        $genomic_feature->{'start'} = $start if $start < $gf_start;
    } else {
        $genomic_feature->{'start'} = $start;
    }

    # Increase end if end from clipboard is greater
    if (my $gf_end = $genomic_feature->{'end'}) {
        $genomic_feature->{'end'} = $end if $end > $gf_end;
    } else {
        $genomic_feature->{'end'} = $end;
    }
    
    # Default the score to 1 if not set
    $genomic_feature->{'score'} ||= 1;
    
    my $text = $genomic_feature->{'display_label'};
    foreach my $id (split /\s+/, $text) {
        $otter->{$id} = 1;
    }
    my $str = join(' ', sort keys %$otter);
    $genomic_feature->{'display_label'} = $str;
}

sub get_otter_ids_of_overlapping_exons {
    my( $self, $name, $start, $end ) = @_;
    
    #warn "Looking for CDS exons in '$name' that overlap $start -> $end";
    
    my $search_exon = Hum::Ace::Exon->new;
    $search_exon->start($start);
    $search_exon->end($end);
    
    my $otter = {};
    my $subseq = $self->XaceSeqChooser->get_SubSeq($name) or return;
    return unless $subseq->translation_region_is_set;
    foreach my $exon ($subseq->get_all_CDS_Exons) {
        if ($exon->overlaps($search_exon)) {
            if (my $id = $exon->otter_id) {
                $otter->{$id} = 1;
            }
        }
    }
    return $otter;
}



# ---------------[getters/setters]----------------

sub write_access {
    my( $self, $write_access ) = @_;

    if (defined $write_access) {
        $self->{_write_access} = $write_access;
    }
    return $self->{_write_access} || 0;
}

sub XaceSeqChooser{
    my ($self , $seq_chooser) = @_ ;
    if ($seq_chooser){

        $self->{_XaceSeqChooser} = $seq_chooser;
    }
    return $self->{_XaceSeqChooser} ;
}

sub slice_name {
    my ($self , $name) = @_ ;
    if ($name){
        $self->{_slice_name} = $name ;
    }
    return $self->{_slice_name} || 'unknown';
}

sub get_CloneSeq {
    my $self = shift @_;
    my $xaceSeqChooser = $self->XaceSeqChooser();
    my $slice_name     = $self->slice_name();
    return ($xaceSeqChooser
        ? $xaceSeqChooser->get_CloneSeq($slice_name)
        : 0
    );
}

sub stored_ace_dump {
    my ($self , $sad) = @_ ;
    if($sad){
        $self->{_sad} = $sad;
    }
    return $self->{_sad};
}


# -------------[create ace representation]---------------------

sub ace_and_vector_dump {
    my($self) = @_;
    
    my $header = qq{Sequence "} . $self->slice_name . qq{"\n};

    my $ace_text = $header."-D Feature\n\n";
    my @vectors = ();

    if(keys %{$self->{_gfs}}) {

        $ace_text .= $header;

        for my $subhash (sort {$a->{start} <=> $b->{start}} values %{$self->{_gfs}}) {
            my $gf_type = $subhash->{gf_type};
            my ($start, $end) =
                ($subhash->{strand} == 1)
                ? ($subhash->{start}, $subhash->{end})
                : ($subhash->{end}, $subhash->{start});
            my $score = $subhash->{score} || $def_score;
            my $display_label = $subhash->{display_label} || $signal_info{$gf_type}{fullname};
            
            $ace_text .= join(' ', 'Feature', qq{"$gf_type"}, $start, $end, $score, qq{"$display_label"\n});

            push @vectors, [ $gf_type, $start, $end, $score, $display_label ];
        }

        $ace_text .= "\n";
    }

    return ($ace_text, \@vectors);
}

# -------------[adding things]-------------------------------

sub create_genomic_feature {
    my ($self, $subframe, $gf_type, $start, $end, $strand, $score, $display_label) = @_;

    my $gfid = ++$self->{_gfid}; # will be uniquely identifying items in the list

    $self->{_gfs}{$gfid} = {
        'start'    => $start,
        'end'      => $end,
        'strand'   => $strand,
        'score'    => $score,
        'display_label' => $display_label,
        'gf_type'  => $gf_type,
        'subframe' => $subframe,
    };

    return ($gfid, $self->{_gfs}{$gfid});
}

sub recalc_coords_callback {
    my ($genomic_feature, $this_key) = @_;

    my $gf_type   = $genomic_feature->{gf_type};
    my $length    = $signal_info{$gf_type}{length};
    my $this_value= $genomic_feature->{$this_key};

    if($length && ($this_value=~/^\d+$/) ) {

        my ($other_key, $diff_sign) = ($this_key eq 'start') ? ('end', 1) : ('start', -1);

        $genomic_feature->{$other_key} =
              $this_value
            + $diff_sign * ($length-1);
    }
}

sub show_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{direction_button}->configure(
        -text => $arrow{$genomic_feature->{strand}}
    );
}

sub paste_label_callback {
    my ($self, $genomic_feature, $this, $x) = @_;
        
    if ($genomic_feature->{'gf_type'} eq 'EUCOMM') {
        $self->paste_eucomm_data($genomic_feature);
    }
    else {
        # We allow the Entry's built in paste behaviour.
        $genomic_feature->{$this}->Paste($x);
    }
}

sub paste_coords_callback {
    my ($self, $genomic_feature, $this) = @_;

    my @ints = $self->integers_from_clipboard();
    if(!@ints) {
        return;
    }

    my $length    = $signal_info{$genomic_feature->{gf_type}}{length};

    if(scalar(@ints)==1) {  # trust the strand information:

        $this ||= ($genomic_feature->{strand} == 1) ? 'start' : 'end';

        $genomic_feature->{$this} = shift @ints;
        if($length) {
            recalc_coords_callback($genomic_feature, $this);
        }

    } else {  # acquire strand information:

        ( $genomic_feature->{start},
          $genomic_feature->{end},
          $genomic_feature->{strand} )
         = ($ints[0]<$ints[1])
            ? ($ints[0], $ints[1],  1)
            : ($ints[1], $ints[0], -1);

        show_direction_callback($genomic_feature);
    }
}

sub flip_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{strand} *= -1;

    show_direction_callback($genomic_feature);
}

sub change_of_gf_type_callback {
    my ($genomic_feature) = @_;

    my $si = $signal_info{$genomic_feature->{gf_type}};
    my @enable  = (-state => 'normal',   -background => 'white');
    my @disable = (-state => 'disabled', -background => 'grey' );
    $genomic_feature->{score_entry}->configure(
        $si->{edit_score} ? @enable : @disable
    );
    $genomic_feature->{display_label_entry}->configure(
        $si->{edit_display_label} ? @enable : @disable
    );
}

sub add_genomic_feature {
    my $self    = shift @_;
    my $gf_type = shift @_;

    my $start   = shift @_ || '';
    my $end     = shift @_ || '';
    my $strand  = shift @_ ||  1;
    my $score   = shift @_ || '';
    my $display_label = shift @_ || '';

    my $subframe = $self->{_metaframe}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );

    my ($gfid, $genomic_feature) = $self->create_genomic_feature(
            $subframe, $gf_type, $start, $end, $strand, $score, $display_label
    );

    my @pack = (-side => 'left', -padx => 2);

    $genomic_feature->{gf_type_menu} = $subframe->Optionmenu(
       -options => [ map { [ $signal_info{$_}{fullname} => $_ ] } signal_keys_in_order() ],
       -variable => \$genomic_feature->{gf_type},
    )->pack(@pack);

    $genomic_feature->{start_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{start},
       -width        => 7,
       -justify      => 'right',
    )->pack(@pack);
    $genomic_feature->{start_entry}->bind('<Return>', sub { recalc_coords_callback($genomic_feature, 'start'); } );

    $genomic_feature->{direction_button} = $subframe->Button(
        -command => sub { flip_direction_callback($genomic_feature); },
    )->pack(-side => 'left');
    show_direction_callback($genomic_feature); # show it once

    $genomic_feature->{end_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{end},
       -width        => 7,
       -justify      => 'right',
    )->pack(@pack);
    $genomic_feature->{end_entry}->bind('<Return>', sub { recalc_coords_callback($genomic_feature, 'end'); } );

    # $genomic_feature->{strand_menu} = $subframe->Optionmenu(
    #   -options => [ map { [ $strand_name{$_} => $_ ] } (keys %strand_name) ],
    #   -variable => \$genomic_feature->{strand},
    # )->pack(@pack);

    $genomic_feature->{score_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{score},
       -width        => 4,
    )->pack(@pack);

    $genomic_feature->{display_label_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{display_label},
       -width        => 24,
    )->pack(@pack);
    my $paste_otter_exon_ids = sub {
        $self->paste_otter_exon_ids($genomic_feature->{display_label_entry});
    };
    $genomic_feature->{display_label_entry}->bind('<Control-e>', $paste_otter_exon_ids);
    $genomic_feature->{display_label_entry}->bind('<Control-E>', $paste_otter_exon_ids);

    my $delete_button = $subframe->Button(
        -text    => 'Delete',
        -command => sub {
            $self->delete_genomic_feature($gfid);
            $self->fix_window_min_max_sizes;
            },
    )->pack(@pack);
    $delete_button->bind('<Destroy>', sub{ $self = undef });
    
        # bindings:

    for my $event ('<<Paste>>', '<Button-2>') {
        $genomic_feature->{'start_entry'}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature, 'start');
            }
        );
        $genomic_feature->{'end_entry'}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature, 'end');
            }
        );
        $genomic_feature->{'direction_button'}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature);
            }
        );
        $genomic_feature->{'display_label_entry'}->bind(
            $event,
            [
                sub {
                    my ($widget, $x) = @_;
                    $self->paste_label_callback($genomic_feature,
                        'display_label_entry', $x);
                },
                Tk::Ev('x')
            ]
        );
    }
    
    ### I don't think we need a destroy for all of these?
    for my $widget ('start_entry', 'end_entry', 'direction_button', 'display_label_entry') {
        $genomic_feature->{$widget}->bind('<Destroy>', sub{ $self=$genomic_feature=undef; } );
    }

        # unfortunately, you cannot bind these before the whole widget is made,
        # as it tends to activate the -command on creation
    $genomic_feature->{gf_type_menu}->configure(
       -command => sub { change_of_gf_type_callback($genomic_feature); },
    );
    # $genomic_feature->{strand_menu}->configure(
    #   -command  => sub { show_direction_callback($genomic_feature); },
    # );

        # It is necessary to set the current value from a separate variable.
        # If you first assign the correct value to a variable and then supply the ref,
        # it will do something opposite to normal intuition: spoil the original value
        # by assigning the one that gets assigned by the interface.
    $genomic_feature->{gf_type_menu}->setOption($signal_info{$gf_type}{fullname}, $gf_type);
    # $genomic_feature->{strand_menu}->setOption($strand_name{$strand}, $strand);
}

sub load_genomic_features {
    my ($self) = @_;

    if (my $clone = $self->get_CloneSeq) {

        foreach my $vector (sort { $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] }
            $clone->get_SimpleFeatures)
        {

            my ($gf_type, $start, $end, $score, $display_label) = @$vector;

            $self->add_genomic_feature($gf_type,
                ($start < $end) ? ($start, $end, 1) : ($end, $start, -1),
                $score, $display_label);
        }
    }

    my ($current_ace_dump, $current_vectors) = $self->ace_and_vector_dump();

    $self->stored_ace_dump($current_ace_dump);

    $self->fix_window_min_max_sizes;
}

# -------------[removing things]-------------------------------

sub delete_genomic_feature {
    my ($self, $gfid) = @_;

    $self->{_gfs}{$gfid}{subframe}->packForget();
    delete $self->{_gfs}{$gfid};
}

sub clear_genomic_features {
    my ($self) = @_;

    for my $gfid (keys %{$self->{_gfs}}) {
        $self->delete_genomic_feature($gfid);
    }
    $self->{_gfs} = undef;
}

# -------------[save if needed (+optional interactivity) ]-------------------

sub save_to_ace {
    my ($self, $force) = @_;

    my ($current_ace_dump, $current_vectors) = $self->ace_and_vector_dump();

    if ($current_ace_dump ne $self->stored_ace_dump()) {

        # Ok, we may need saving - but do we want it?
        if(! $force) {
            
            my $save_changes = $self->top_window->messageBox(
                -title      => "Save genomic features for " ,
                -message    => "Do you wish to save the changes for '" . $self->slice_name . "'?",
                -type       => 'YesNo',
                -icon       => 'question',
                -default    => 'Yes',
            );

            if($save_changes eq 'No') {
                return;
            }
        }
        
        if($self->XaceSeqChooser()->update_ace_display($current_ace_dump)) {
            print STDERR "Genomic features successfully saved to acedb\n";

                # after saving it becomes the 'current' version:
            $self->stored_ace_dump($current_ace_dump);

                # Make the clone know the new vectors
            $self->get_CloneSeq->set_SimpleFeatures(@$current_vectors);
        } else {
            print STDERR "There was an error saving genomic features to acedb\n";
        }
    }
}

# ---[attempt to save if needed, then destroy the window]------

sub try2save_and_quit {
    my $self = shift @_;

    if($self->XaceSeqChooser()) {
        $self->save_to_ace(0); # '0' means do it interactively
    } else {
        print STDERR "No XaceSeqChooser, nowhere to write\n";
    }

    $self->top_window->destroy();
}

# -------------[fill it in]------------------------------------

sub initialize {
    my($self) = @_;

    my $top_window = $self->top_window();

    my $file_menu = $self->make_menu('File');
    my $reload = sub {
        $self->clear_genomic_features();
        $self->load_genomic_features()
        };
    $file_menu->command(
        -label          => 'Reload',
        -command        => $reload,
        -accelerator    => 'Ctrl+R',
        -underline      => 1,
    );
    $top_window->bind('<Control-R>', $reload) ;
    $top_window->bind('<Control-r>', $reload) ;

    my $save = sub { $self->save_to_ace(1); }; # '1' means skip interactivity
    $file_menu->command(
        -label          => 'Save',
        -command        => $save,
        -accelerator    => 'Ctrl+S',
        -underline      => 1,
    );    
    $top_window->bind('<Control-S>', $save);
    $top_window->bind('<Control-s>', $save);

    my $close = sub { $self->try2save_and_quit() };
    $file_menu->command(
        -label          => 'Close',
        -command        => $close,
        -accelerator    => 'Ctrl+W',
        -underline      => 1,
    );
    $top_window->protocol('WM_DELETE_WINDOW', $close);
    $top_window->bind('<Control-W>', $close);
    $top_window->bind('<Control-w>', $close);

    my $add_menu = $self->make_menu('Add feature');
    for my $gf_type (signal_keys_in_order()) {
        my $fullname = $signal_info{$gf_type}{fullname};
        my $length   = $signal_info{$gf_type}{length};

        $add_menu->command(
            -label   => $fullname.($length ? " (${length}bp)" : ''),
            -command => sub {
                $self->add_genomic_feature($gf_type);
                $self->fix_window_min_max_sizes;
                # Scroll window so new widgets are visible
                $self->canvas->yviewMoveto(1);
                },
        );
    }

    if(! $self->write_access()) {
        $self->menu_bar()->Label(
            -text       => 'Read Only',
            -foreground => 'red',
            -padx       => 6,
        )->pack(
            -side => 'right',
        );
    }

    $self->{_metaframe} = $self->canvas->Frame();
    $self->canvas->createWindow( 5, 5,
        -window => $self->{_metaframe},
        -anchor => 'nw',
        -tags => 'metaframe',
    );
    $self->canvas->configure(-background => $self->{_metaframe}->cget('-background') );

    $self->load_genomic_features();


    my $tl = $self->top_window;
    $tl->title("Genomic features for '".$self->slice_name()."'");
    
    $self->canvas->Tk::bind('<Destroy>', sub{ $self = undef });
}

1;

__END__

=head1 NAME - MenuCanvasWindow::GenomicFeatures

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

