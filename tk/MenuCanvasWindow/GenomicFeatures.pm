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
     1 => 'Fwd',
    -1 => 'Rev',
);

my $def_score = 0.5;

# --------------- order-encoded-strand manupulation subroutines ------------

sub order_coords_by_strand {
    my ($coord1, $coord2, $strand) = @_;

    return sort { ($a <=> $b)*$strand } ($coord1, $coord2);
}

sub get_strand_from_order {
    my ($coord1, $coord2) = @_;

    return ($coord1>$coord2) ? -1 : 1;
}

# ---------------[EUCOMM]----------------

sub paste_eucomm_data {
    my ($self, $genomic_feature) = @_;

    my ($class, $name, $clip_start, $clip_end) =
      $self->class_object_start_end_from_clipboard;
    if (!$class or $class ne 'Sequence') {
        return;
    }

    if ($clip_start > $clip_end) {
        ($clip_start, $clip_end) = ($clip_end, $clip_start);
    }

    # Parse the old otter exon IDs from the existing text field
    my $display_otter = {};
    my $text = $genomic_feature->{display_label};
    foreach my $id (grep /E\d{11}$/, split /[^A-Z0-9]+/, $text) {
        $display_otter->{$id} = 1;
    }

    my ($otter, $start, $end, $strand, $exon_length) =
      $self->get_overlapping_exon_otter_id_start_end($name, $clip_start, $clip_end, $display_otter);

    # Don't change anything if search failed
    return unless $otter;

    ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime})
        = order_coords_by_strand($start, $end, $strand);

    # Default the score to 1 if not set
    $genomic_feature->{score} ||= 1;

    my $count = keys %$otter;
    my $str = sprintf "%d exon%s phase %d from %s (%s)",
        $count,
        $count > 1 ? 's' : '',
        $exon_length % 3,
        $name,
        join(' ', sort keys %$otter);
    $genomic_feature->{display_label} = $str;
}

sub get_overlapping_exon_otter_id_start_end {
    my ($self, $name, $search_start, $search_end, $display_otter) = @_;

    #warn "Looking for CDS exons in '$name' that overlap $start -> $end";

    my $search_exon = Hum::Ace::Exon->new;
    $search_exon->start($search_start);
    $search_exon->end($search_end);

    my $subseq = $self->XaceSeqChooser->get_SubSeq($name) or return;
    return unless $subseq->translation_region_is_set;

    my $strand = $subseq->strand();
    my $new_otter = {};
    my $exon_length_total = 0;
    my ($start, $end);
    my $in_zone = 0;
    #warn "Looking for $search_start - $search_end and (", join(', ', map "'$_'", keys %$display_otter), ")";
    foreach my $exon ($subseq->get_all_CDS_Exons) {
        my $id = $exon->otter_id
          or next;
        #warn "Looking at '$id'\n";
        if ($display_otter->{$id} or $exon->overlaps($search_exon)) {
            #warn "Found exon '$id'\n";
            $in_zone = 1;
            $new_otter->{$id} = 1;
            $exon_length_total += $exon->length;
            if ($start) {
                $start = $exon->start if $exon->start < $start;
            } else {
                $start = $exon->start;
            }
            if ($end) {
                $end = $exon->end if $exon->end > $end;
            } else {
                $end = $exon->end;
            }
        } else {
            # Makes it impossible to select non-consecutive exons
            last if $in_zone;
        }
    }
    if ($in_zone) {
        return ($new_otter, $start, $end, $strand, $exon_length_total);
    } else {
        return;
    }
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

        $self->{'_XaceSeqChooser'} = $seq_chooser;
    }
    return $self->{'_XaceSeqChooser'} ;
}

sub slice_name {
    my ($self) = @_ ;
    
    return $self->XaceSeqChooser->slice_name;
}

sub get_CloneSeq {
    my $self = shift @_;

    return $self->XaceSeqChooser->get_CloneSeq;
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
    my ($self) = @_;

    my $header = qq{Sequence "} . $self->slice_name . qq{"\n};

    my $ace_text = $header;
    for my $ftype (keys %signal_info) { # only delete "known" features, not any
        $ace_text .= qq{-D Feature "$ftype"\n};
    }
    $ace_text .= "\n";

    my @vectors  = ();

    my $valid_gfs = [ grep { $_ && $_->{fiveprime} && $_->{threeprime} }
                      (values %{ $self->{_gfs} }) ];

    if(@$valid_gfs) {

        $ace_text .= $header;

        for my $subhash (
            sort { (($a->{fiveprime}<$a->{threeprime})?$a->{fiveprime}:$a->{threeprime})
               <=> (($b->{fiveprime}<$b->{threeprime})?$b->{fiveprime}:$b->{threeprime}) }
                 @$valid_gfs )
        {
            my $gf_type = $subhash->{gf_type};
            my ($start, $end) =
                order_coords_by_strand($subhash->{fiveprime}, $subhash->{threeprime}, $subhash->{strand});

            my $score = $subhash->{score} || $def_score;
            my $display_label = $subhash->{display_label} || $gf_type;

            $ace_text .= join(' ',
                'Feature', qq{"$gf_type"}, $start, $end, $score,
                qq{"$display_label"\n});

            push @vectors, [ $gf_type, $start, $end, $score, $display_label ];
        }

        $ace_text .= "\n";
    }

    return ($ace_text, \@vectors);
}

# -------------[adding things]-------------------------------

sub create_genomic_feature {
    my ($self, $subframe, $gf_type, $fiveprime, $threeprime, $strand, $score, $display_label) = @_;

    my $gfid = ++$self->{_gfid}; # will be uniquely identifying items in the list

    $self->{_gfs}{$gfid} = {
        'fiveprime'     => $fiveprime,
        'threeprime'    => $threeprime,
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

        my ($other_key, $diff_sign) = ($this_key eq 'fiveprime') ? ('threeprime', 1) : ('fiveprime', -1);

        $genomic_feature->{$other_key} =
              $this_value
            + $diff_sign * $genomic_feature->{strand} * ($length-1);
    }
}

sub show_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{direction_button}->configure(
        -text => $strand_name{$genomic_feature->{strand}}
    );
}

sub paste_label_callback {
    my ($self, $genomic_feature, $this, $x) = @_;
        
    if ($genomic_feature->{'gf_type'} eq 'EUCOMM') {
        $self->paste_eucomm_data($genomic_feature);
        return 1;
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

        $this ||= ($genomic_feature->{strand} == 1) ? 'fiveprime' : 'threeprime';

        $genomic_feature->{$this} = shift @ints;
        if($length) {
            recalc_coords_callback($genomic_feature, $this);
        }

    } else {  # acquire strand information:

        ( $genomic_feature->{fiveprime}, $genomic_feature->{threeprime} )
            = ($ints[0], $ints[1]);
        $genomic_feature->{strand} = get_strand_from_order($ints[0], $ints[1]);

        show_direction_callback($genomic_feature);
    }
}

sub flip_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{strand} *= -1;

    if( $genomic_feature->{fiveprime} && $genomic_feature->{threeprime} ) {
        ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime}) = 
            order_coords_by_strand(map { $genomic_feature->{$_} } ('fiveprime', 'threeprime', 'strand'));
    } else { # just swap them
        ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime}) =
            ($genomic_feature->{threeprime}, $genomic_feature->{fiveprime});
    }

    show_direction_callback($genomic_feature);
}

sub change_of_gf_type_callback {
    my ($genomic_feature, $wanted_type) = @_;

    my $display_label_was_fake      # it was either empty or simply matched gf_type:
        =  (not $genomic_feature->{display_label})
        || ($genomic_feature->{gf_type} eq $genomic_feature->{display_label});

    $genomic_feature->{gf_type} = $wanted_type;

    my $si = $signal_info{$wanted_type};

    if($display_label_was_fake) {
        $genomic_feature->{display_label} = $si->{edit_display_label}
            ? ''            # clean it
            : $wanted_type; # let it remain a fake label
    } else {
        # let's assume it contained something precious
    }

    my @enable  = (-state => 'normal',   -background => 'white');
    my @disable = (-state => 'disabled', -background => 'grey' );
    $genomic_feature->{score_entry}->configure(
        $si->{edit_score}         ? @enable : @disable
    );
    $genomic_feature->{display_label_entry}->configure(
        $si->{edit_display_label} ? @enable : @disable
    );
}

sub add_genomic_feature {
    my $self    = shift @_;
    my $gf_type = shift @_;

    my $fiveprime    = shift @_ || '';
    my $threeprime   = shift @_ || '';
    my $strand  = shift @_ ||  1;
    my $score   = shift @_ || '';
    my $display_label = shift @_ || $gf_type;

    my $subframe = $self->{_metaframe}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );

    my ($gfid, $genomic_feature) = $self->create_genomic_feature(
            $subframe, $gf_type, $fiveprime, $threeprime, $strand, $score, $display_label
    );

    my @pack = (-side => 'left', -padx => 2);

    $genomic_feature->{gf_type_menu} = $subframe->Optionmenu(
       -options  => [ map { [ $signal_info{$_}{fullname} => $_ ] } signal_keys_in_order() ],
    )->pack(@pack);

    $genomic_feature->{fiveprime_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{fiveprime},
       -width        => 7,
       -justify      => 'right',
    )->pack(@pack);
    my $recalc_fiveprime = sub { recalc_coords_callback($genomic_feature, 'fiveprime'); };
    $genomic_feature->{fiveprime_entry}->bind('<Return>', $recalc_fiveprime);
    $genomic_feature->{fiveprime_entry}->bind('<Up>',     $recalc_fiveprime);
    $genomic_feature->{fiveprime_entry}->bind('<Down>',   $recalc_fiveprime);

    $genomic_feature->{direction_button} = $subframe->Button(
        -command => sub { flip_direction_callback($genomic_feature); },
    )->pack(-side => 'left');
    show_direction_callback($genomic_feature); # show it once

    $genomic_feature->{threeprime_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{threeprime},
       -width        => 7,
       -justify      => 'right',
    )->pack(@pack);
    my $recalc_threeprime = sub { recalc_coords_callback($genomic_feature, 'threeprime'); };
    $genomic_feature->{threeprime_entry}->bind('<Return>', $recalc_threeprime);
    $genomic_feature->{threeprime_entry}->bind('<Up>',     $recalc_threeprime);
    $genomic_feature->{threeprime_entry}->bind('<Down>',   $recalc_threeprime);

    $genomic_feature->{score_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{score},
       -width        => 4,
    )->pack(@pack);

    my $delete_button = $subframe->Button(
        -text    => 'Delete',
        -command => sub {
            $self->delete_genomic_feature($gfid);
            $self->set_scroll_region_and_maxsize;
            },
    )->pack(@pack);
    
    # Break circular reference caused by closure
    $delete_button->bind('<Destroy>', sub{ $self = undef });
    
    $genomic_feature->{display_label_entry} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{display_label},
       -width        => 24,
    )->pack(@pack);

        # bindings:

    for my $event ('<<Paste>>', '<Button-2>') {
        $genomic_feature->{fiveprime_entry}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature, 'fiveprime');
            }
        );
        $genomic_feature->{threeprime_entry}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature, 'threeprime');
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
                Tk::Ev('x') # Needed by default Entry paste handler
            ]
        );
    }
    
    ### I don't think we need a destroy for all of these?
    for my $widget ('fiveprime_entry', 'threeprime_entry', 'direction_button', 'display_label_entry') {
        $genomic_feature->{$widget}->bind('<Destroy>', sub{ $self=$genomic_feature=undef; } );
    }

        # unfortunately, you cannot bind these before the whole widget is made,
        # as it tends to activate the -command on creation
    $genomic_feature->{gf_type_menu}->configure(
       -command => sub { change_of_gf_type_callback($genomic_feature, shift @_); },
    );

    # It is necessary to set the current value from a separate variable.
    # If you first assign the correct value to a variable and then supply the ref,
    # it will do something opposite to normal intuition: spoil the original value
    # by assigning the one that gets assigned by the interface.
    $genomic_feature->{gf_type_menu}->setOption($signal_info{$gf_type}{fullname}, $gf_type);
}

sub load_genomic_features {
    my ($self) = @_;

    if (my $clone = $self->get_CloneSeq) {

        foreach my $vector (sort { $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] }
            $clone->get_SimpleFeatures([keys %signal_info]) )
        {

            my ($gf_type, $fiveprime, $threeprime, $score, $display_label) = @$vector;

            my $strand = get_strand_from_order($fiveprime, $threeprime);
            $self->add_genomic_feature($gf_type, $fiveprime, $threeprime, $strand,
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
    $self->{_gfs} = {};
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
                # $self->fix_window_min_max_sizes;
                $self->set_scroll_region_and_maxsize;

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
            -side       => 'right',
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

