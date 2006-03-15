## MenuCanvasWindow::GenomicFeatures

package MenuCanvasWindow::GenomicFeatures;

use strict;
use base 'MenuCanvasWindow';

my %signal_info = (
    'polyA_signal' => {
        'length'   => 6,
        'fullname' => 'PolyA signal',
    },
    'polyA_site' => {
        'length'   => 2,
        'fullname' => 'PolyA site',
    },
    'pseudo_polyA' => {
        'length'   => 6,
        'fullname' => 'Pseudo-PolyA signal',
    },
    'TATA_box' => {
        'length'   => 8,
        'fullname' => 'TATA-box',
    },
    'RSS'    => {
        'fullname' => 'Recombination signal sequence',
    },
    'EUCOMM' => {
        'fullname'  => 'exon(s) targetted for EUCOMM knockout',
        'edit_score'         => 1,
        'edit_display_label' => 1,
    },
);

my %strand_name = (
     1 => 'forward',
    -1 => 'reverse',
);

my %arrow = (
     1 => '==>',
    -1 => '<==',
);

my $def_score = 0.5;

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
            my $display_label = $subhash->{display_labe} || $signal_info{$gf_type}{fullname};
            
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

sub recalc_coords_via_length {
    my ($genomic_feature, $this_key) = @_;

    my $gf_type   = $genomic_feature->{gf_type};
    my $length    = $signal_info{$gf_type}{length};
    my $this_value= $genomic_feature->{$this_key};

    if($length && ($this_value=~/^\d+$/) ) {

        my ($other_key, $diff_sign) = ($this_key eq 'start') ? ('end', 1) : ('start', -1);

        $genomic_feature->{$other_key} =
              $this_value
            + $diff_sign * $genomic_feature->{strand} * ($length-1);
    }
}

sub start_stop_strand_from_clipboard {
    my $self = shift @_;

    my @ints = $self->integers_from_clipboard();
    if(scalar(@ints) != 2) {
        return ('', '', 1);
    } elsif($ints[0]<$ints[1]) {
        return ($ints[0], $ints[1], 1);
    } else {
        return ($ints[1], $ints[0], -1);
    }
}

sub paste_coords_callback {
    my ($self, $genomic_feature) = @_;

    my ($clip_start, $clip_end, $clip_strand) = $self->start_stop_strand_from_clipboard();
    if($clip_start) {
        $genomic_feature->{start}  = $clip_start;
        $genomic_feature->{end}    = $clip_end;

            # strictly in this order!
        $genomic_feature->{strand_menu}->setOption($strand_name{$clip_strand}, $clip_strand);
        $genomic_feature->{strand} = $clip_strand;
    }
}

sub change_of_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{direction_arrow}->configure(
        -text => $arrow{$genomic_feature->{strand}}
    );
}

sub change_of_gf_type_callback {
    my ($genomic_feature) = @_;

    my $si = $signal_info{$genomic_feature->{gf_type}};
    $genomic_feature->{score_entry}->configure(
        -state => $si->{edit_score} ? 'normal' : 'disabled'
    );
    $genomic_feature->{display_label_entry}->configure(
        -state => $si->{edit_display_label} ? 'normal' : 'disabled'
    );
}

sub add_genomic_feature {
    my $self    = shift @_;
    my $gf_type = shift @_;

    # my ($clip_start, $clip_end, $clip_strand) = $self->start_stop_strand_from_clipboard();

    my $start   = shift @_ || ''; # $clip_start;
    my $end     = shift @_ || ''; # $clip_end;
    my $strand  = shift @_ ||  1; # $clip_strand;
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
       -options => [ map { [ $signal_info{$_}{fullname} => $_ ] } (keys %signal_info) ],
       -variable => \$genomic_feature->{gf_type},
    )->pack(@pack);

    $genomic_feature->{start_entry} = $subframe->Entry(
       -textvariable => \$genomic_feature->{start},
       -width        => 10,
    )->pack(@pack);
    $genomic_feature->{start_entry}->bind('<Return>', sub { recalc_coords_via_length($genomic_feature, 'start'); } );

    $genomic_feature->{direction_arrow} = $subframe->Label(
    )->pack(@pack);

    $genomic_feature->{end_entry} = $subframe->Entry(
       -textvariable => \$genomic_feature->{end},
       -width        => 10,
    )->pack(@pack);
    $genomic_feature->{end_entry}->bind('<Return>', sub { recalc_coords_via_length($genomic_feature, 'end'); } );

    $genomic_feature->{strand_menu} = $subframe->Optionmenu(
       -options => [ map { [ $strand_name{$_} => $_ ] } (keys %strand_name) ],
       -variable => \$genomic_feature->{strand},
    )->pack(@pack);

    $genomic_feature->{score_entry} = $subframe->Entry(
       -textvariable => \$genomic_feature->{score},
       -width        => 10,
    )->pack(@pack);

    $genomic_feature->{display_label_entry} = $subframe->Entry(
       -textvariable => \$genomic_feature->{display_label},
       -width        => 10,
    )->pack(@pack);

    my $delete_button = $subframe->Button(
        -text    => 'Delete',
        -command => sub {
            $self->delete_genomic_feature($gfid);
            $self->fix_window_min_max_sizes;
            },
    )->pack(@pack);
    $delete_button->bind('<Destroy>', sub{ $self = undef });
    
        # bindings:
    my $paste_callback = sub { $self->paste_coords_callback($genomic_feature); };

    for my $widget ('gf_type_menu', 'start_entry', 'end_entry', 'strand_menu') {
        for my $event ('<<Paste>>', '<ButtonRelease-2>') {
            $genomic_feature->{$widget}->bind($event, $paste_callback);
        }
        $genomic_feature->{$widget}->bind('<Destroy>', sub{ $self=$genomic_feature=undef; } );
    }

        # unfortunately, you cannot bind these before the whole widget is made,
        # as it tends to activate the -command on creation
    $genomic_feature->{gf_type_menu}->configure(
       -command => sub { change_of_gf_type_callback($genomic_feature); },
    );
    $genomic_feature->{strand_menu}->configure(
       -command  => sub { change_of_direction_callback($genomic_feature); },
    );

        # It is necessary to set the current value from a separate variable.
        # If you first assign the correct value to a variable and then supply the ref,
        # it will do something opposite to normal intuition: spoil the original value
        # by assigning the one that gets assigned by the interface.
    $genomic_feature->{gf_type_menu}->setOption($signal_info{$gf_type}{fullname}, $gf_type);
    $genomic_feature->{strand_menu}->setOption($strand_name{$strand}, $strand);
}

sub load_genomic_features {
    my ($self) = @_;

    if (my $clone = $self->get_CloneSeq){

        foreach my $vector ( $clone->get_SimpleFeatures('') ) {

            my ($gf_type, $start, $end, $score, $display_label) = @$vector;

            $self->add_genomic_feature(
                $gf_type,
                ($start<$end) ? ($start, $end, 1) : ($end, $start, -1),
                $score,
                $display_label
            );
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

    if($current_ace_dump ne $self->stored_ace_dump()) {

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

if(0) {
    $self->{_direction} = -1;
    my $view_menu = $self->make_menu('View');
    $view_menu->radiobutton(
        -label    => 'Along ~assembly mode',
        -variable => \$self->{_direction},
        -value    => -1,
        -command  => sub { print STDERR "along assembly mode\n"; },
    );
    $view_menu->radiobutton(
        -label    => '~Left-to-right mode',
        -variable => \$self->{_direction},
        -value    =>  1,
        -command  => sub { print STDERR "left-to-right mode\n"; },
    );
}

    my $add_menu = $self->make_menu('Add genomic feature');
    for my $gf_type (keys %signal_info) {
        my $fullname = $signal_info{$gf_type}{fullname};
        my $length   = $signal_info{$gf_type}{length};

        $add_menu->command(
            -label   => $fullname.($length ? " (${length}bp)" : ''),
            -command => sub {
                $self->add_genomic_feature($gf_type);
                $self->fix_window_min_max_sizes;
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

