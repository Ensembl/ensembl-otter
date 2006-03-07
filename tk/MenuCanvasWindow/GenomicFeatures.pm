## MenuCanvasWindow::GenomicFeatures

package MenuCanvasWindow::GenomicFeatures;

use strict;
use base 'MenuCanvasWindow';

my %signal_info = (
    'polyA_signal' => {
                        'length' => 6,
                        'fullname'  => 'PolyA signal',
                    },
    'polyA_site'   => {
                        'length' => 2,
                        'fullname'  => 'PolyA site',
                    },
    'pseudo_polyA' => {
                        'length' => 6,
                        'fullname'  => 'Pseudo-PolyA signal',
                    },
    'TATA_box' => {
                        'length' => 8,
                        'fullname'  => 'TATA-box',
                    },
    'RSS' => {
                        'length' => '?',
                        'fullname'  => 'Recombination signal sequence',
                    },
);

my %strand_name = (
     1 => 'forward',
    -1 => 'reverse',
);

my $score = 0.5;

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
    
    my $header = 'Sequence "'.$self->slice_name().qq{"\n};

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
            my $display_label = $signal_info{$gf_type}{fullname};
            
            $ace_text .= join(' ', 'Feature ', qq{"$gf_type"}, $start, $end, $score, qq{"$display_label"\n});

            push @vectors, [ $gf_type, $start, $end, $score, $display_label ];
        }

        $ace_text .= "\n";
    }

    return ($ace_text, \@vectors);
}

# -------------[adding things]-------------------------------

sub create_genomic_feature {
    my ($self, $subframe, $gf_type, $start, $end, $strand) = @_;

    my $gfid = ++$self->{_gfid}; # will be uniquely identifying items in the list

    $self->{_gfs}{$gfid} = {
        'start'    => $start,
        'end'      => $end,
        'strand'   => $strand,
        'gf_type'  => $gf_type,
        'subframe' => $subframe,
    };

    return ($gfid, $self->{_gfs}{$gfid});
}

sub add_genomic_feature {

    my $self    = shift @_;
    my $gf_type = shift @_;

    my ($clip_start, $clip_end) = ($self->integers_from_clipboard(), '', '');
    my $clip_strand = 1;
    if($clip_start && $clip_end && ($clip_start > $clip_end)) {
        ($clip_start, $clip_end) = ($clip_end, $clip_start);
        $clip_strand = -1;
    }

    my $start   = shift @_ || $clip_start;
    my $end     = shift @_ || $clip_end;
    my $strand  = shift @_ || $clip_strand;

    my $subframe = $self->{_metaframe}->Frame()->pack(
        -padx   => 5,
        -pady   => 5,
        -fill   => 'x',
        -expand => 1,
    );

    my ($gfid, $genomic_feature) = $self->create_genomic_feature(
            $subframe, $gf_type, $start, $end, $strand
    );

    my $gf_type_menu = $subframe->Optionmenu(
       -options => [ map { [ $signal_info{$_}{fullname} => $_ ] } (keys %signal_info) ],
       -variable => \$genomic_feature->{gf_type},
       -relief       => 'flat',
    )->pack(-side => 'left');

        # It is necessary to set the current value from a separate variable.
        # If you first assign the correct value to a variable and then supply the ref,
        # it will do something opposite to normal intuition: spoil the original value
        # by assigning the one that gets assigned by the interface.
    $gf_type_menu->setOption($signal_info{$gf_type}{fullname}, $gf_type);

    my $start_entry = $subframe->Entry(
       -textvariable => \$genomic_feature->{start},
       -width        => 10,
       -relief       => 'sunken',
    )->pack(-side => 'left');

    my $end_entry = $subframe->Entry(
       -textvariable => \$genomic_feature->{end},
       -width        => 10,
       -relief       => 'sunken',
    )->pack(-side => 'left');

    my $strand_menu = $subframe->Optionmenu(
       -options => [ map { [ $strand_name{$_} => $_ ] } (keys %strand_name) ],
       -variable => \$genomic_feature->{strand},
       -relief       => 'flat',
    )->pack(-side => 'left');

        # It is necessary to set the current value from a separate variable.
        # If you first assign the correct value to a variable and then supply the ref,
        # it will do something opposite to normal intuition: spoil the original value
        # by assigning the one that gets assigned by the interface.
    $strand_menu->setOption($strand_name{$strand}, $strand);

    my $delete_button = $subframe->Button(
        -text    => 'Delete',
        -command => sub { $self->delete_genomic_feature($gfid) },
    )->pack (-side => 'left');

    $self->fix_window_min_max_sizes;
}

sub load_genomic_features {
    my ($self) = @_;

    if (my $clone = $self->get_CloneSeq){

        foreach my $vector ( $clone->get_SimpleFeatures('') ) {

            my ($gf_type, $start, $end) = @$vector;

            $self->add_genomic_feature(
                $gf_type,
                ($start<$end) ? ($start, $end, 1) : ($end, $start, -1)
            );
        }
    }

    my ($current_ace_dump, $current_vectors) = $self->ace_and_vector_dump();

    $self->stored_ace_dump($current_ace_dump);
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

    $self->save_to_ace(0); # '0' means do it interactively

    $self->top_window->destroy();
    if(my $xaceseqchooser = $self->XaceSeqChooser()) {
        $xaceseqchooser->GenomicFeatures('');
    }
}

# -------------[fill it in]------------------------------------

sub initialize {
    my($self) = @_;

    my $file_menu = $self->make_menu('File');
    $file_menu->add('command',
        -label          => 'Reload',
        -command        => sub { $self->clear_genomic_features(); $self->load_genomic_features() },
        -accelerator    => 'Ctrl+R',
        -underline      => 1,
    );    
    $file_menu->add('command',
        -label          => 'Save',
        -command        => sub { $self->save_to_ace(1) }, # '1' means skip interactivity
        -accelerator    => 'Ctrl+S',
        -underline      => 1,
    );    
    $file_menu->add('command',
        -label          => 'Quit',
        -command        => sub { $self->try2save_and_quit() },
        -accelerator    => 'Ctrl+Q',
        -underline      => 1,
    );    

    my $top_window = $self->top_window();

    $top_window->protocol('WM_DELETE_WINDOW', sub {$self->try2save_and_quit();} );
    $top_window->bind('<Control-S>' , sub { $self->save_to_ace(1); } ) ;
    $top_window->bind('<Control-s>' , sub { $self->save_to_ace(1); } ) ;


    my $add_menu = $self->make_menu('Add genomic feature');
    for my $gf_type (keys %signal_info) {
        my $fullname = $signal_info{$gf_type}{fullname};
        my $length   = $signal_info{$gf_type}{length};

        $add_menu->add('command',
            -label   => "$fullname (${length}bp)",
            -command => sub { $self->add_genomic_feature($gf_type); },
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
}

1;

__END__

=head1 NAME - MenuCanvasWindow::GenomicFeatures

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

