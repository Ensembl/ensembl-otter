
### MenuCanvasWindow::XaceSeqChooser

package MenuCanvasWindow::XaceSeqChooser;

use strict;
use 5.006_001;  # For qr support
use Carp qw{ cluck confess };
use Tk::Dialog;
use Symbol 'gensym';
use Scalar::Util 'weaken';

use Hum::Ace::SubSeq;
use Hum::Ace::Locus;
use Hum::Ace::Method;
use Hum::Ace::XaceRemote;
use Hum::Ace::DotterLauncher;
use Hum::Ace;
use Hum::Analysis::Factory::ExonLocator;
use MenuCanvasWindow::ExonCanvas;
use CanvasWindow::DotterWindow;
use MenuCanvasWindow::GenomicFeatures;
use Bio::Otter::Lace::Defaults;

use base 'MenuCanvasWindow';

#use MenuCanvasWindow::ZMapSeqChooser;

sub new {
    my( $pkg, $tk ) = @_;
    
    my $self = $pkg->SUPER::new($tk);

    $self->populate_menus;
    $self->bind_events;
    $self->minimum_scroll_bbox(0,0, 300,200);
    return $self;
}

sub Client {
    my( $self, $Client ) = @_;
     
    if ($Client) {
        $self->{'_Client'} = $Client;
    } 
    return $self->{'_Client'};
}

sub AceDatabase {
    my( $self, $AceDatabase ) = @_;
    
    if ($AceDatabase) {
        $self->{'_AceDatabase'} = $AceDatabase;
    }
    return $self->{'_AceDatabase'};
}

sub SequenceNotes {
    my ($self, $sn) = @_ ;
    
    if ($sn){
        $self->{'_sequence_notes'} = $sn ;
    }
    return $self->{'_sequence_notes'} ;
}

sub EviCollection {
    my( $self, $EviCollection ) = @_;
    
    if ($EviCollection) {
        $self->{'_EviCollection'} = $EviCollection;
    }
    return $self->{'_EviCollection'};
}

sub initialize {
    my( $self ) = @_;
    
    # take GeneMethods from methods.ace file
    $self->set_known_GeneMethods();
    
    $self->draw_subseq_list;
    
    $self->populate_Features_menu;
    
    $self->_make_search;
    unless ($self->write_access) {
        $self->menu_bar()->Label(
            -text       => 'Read Only',
            -foreground => 'red',
            -padx       => 6,
            )->pack(
                    -side => 'right',
                    );
    }
    $self->fix_window_min_max_sizes;
}

sub write_access {
    my( $self, $write_access ) = @_;
    
    if (defined $write_access) {
        $self->{'_write_access'} = $write_access;
    }
    return $self->{'_write_access'} || 0;
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

# this method has been moved to Bio::Otter::Lace::Defaults.pm
# but this has been left for backwards compatibility
sub set_known_GeneMethods_via_Defaults{
    my ($self) = @_ ;
    Bio::Otter::Lace::Defaults->set_known_GeneMethods($self) ;
}

sub set_known_GeneMethods{
    my ($self) = @_ ;

    my $collection = $self->AceDatabase->get_default_MethodCollection;
    foreach my $method (@{$collection->get_all_Methods}) {
        if ($method->transcript_type) {
            $self->add_GeneMethod($method);
        }
    }
}

sub fetch_GeneMethod {
    my( $self, $name ) = @_;
    
    confess "Missing name argument" unless $name;
    my $ace = $self->ace_handle;
    $ace->raw_query("find Method $name");
    my $txt = Hum::Ace::AceText->new($ace->raw_query('show -a'));
    my( $meth );
    if ($txt->count_tag('Method')) {
        $meth = Hum::Ace::Method->new_from_AceText($txt);
    } else {
        warn "Making method not in db: '$name'\n";
        $meth = Hum::Ace::Method->new;
        $meth->name($name);
        $meth->color('BLUE');
        $meth->cds_color('MIDBLUE');
    }
    return $meth;
}

sub add_GeneMethod {
    my( $self, $meth ) = @_;
    
    my $name = $meth->name;
    $self->{'_gene_methods'}{$name} = $meth;
    my $list = $self->{'_gene_methods_list'} ||= [];
    push(@$list, $meth);
}

sub get_GeneMethod {
    my( $self, $name ) = @_;
    
    my( $meth );
    unless ($meth = $self->{'_gene_methods'}{$name}) {
        $meth = $self->fetch_GeneMethod($name)
            or confess "No such Method '$name'";
        $self->add_GeneMethod($meth);
    }
    return $meth;
}

sub get_all_GeneMethods {
    my( $self ) = @_;
    
    return values %{$self->{'_gene_methods'}};
}

sub get_all_mutable_GeneMethods {
    my( $self ) = @_;
    
    my $list = $self->{'_gene_methods_list'} || [];
    return grep $_->mutable, @$list;
}

sub get_default_mutable_GeneMethod {
    my( $self ) = @_;
   
    my @possible = grep $_->transcript_type eq 'coding', $self->get_all_mutable_GeneMethods;
    if (my ($supp) = grep $_->name eq 'Coding', @possible) {
        # "Coding" is the default method, if it is there
        return $supp;
    }
    elsif (@possible)  {
        return $possible[0];
    } else {
        $self->message("Unable to get a default GeneMethod");
        return;
    }
}

sub update_ace_display {
    my ($self, $ace) = @_ ;
    
    
    my $xr = $self->xace_remote || $self->open_xace_dialogue;
    
    if ($xr) {
        print STDERR "Sending:\n$ace";
        $xr->load_ace($ace);
        $xr->save;
        $xr->send_command('gif ; seqrecalc');
        
        return 1;
    } else {
        $self->message("No xace attached");
        print STDERR "not able to send .ace file - no xace attached";
        return 0;
    }    
}

# this should be called when a user tries to save, but no Xace is opened
sub open_xace_dialogue{
    my ($self) = @_ ;
    
    my $answer = $self->top_window()->messageBox(-title => 'Please Reply', 
     -message => 'No Xace attached, would you like to launch Xace?', 
     -type => 'YesNo', -icon => 'question', -default => 'Yes');

    if ($answer eq 'Yes'){
        $self->launch_xace();
    }
    return $self->xace_remote;
}

sub get_Locus {
    my( $self, $name ) = @_;
    
    my( $locus );
    if (ref($name)) {
        $locus = $name;
        $name = $locus->name;
    }
    
    if (my $cached = $self->{'_locus_cache'}{$name}) {
        return $cached;
    } else {
        unless ($locus) {
            $locus = Hum::Ace::Locus->new;
            $locus->name($name);
        }
        $self->{'_locus_cache'}{$name} = $locus;
        return $locus;
    }
}

sub set_Locus {
    my( $self, $locus ) = @_;
    
    my $name = $locus->name;
    $self->{'_locus_cache'}{$name} = $locus;
}

sub get_all_Loci {
    my( $self ) = @_;    
    my $lc = $self->{'_locus_cache'};
    return values %$lc;
}

sub list_Locus_names {
    my( $self ) = @_;    
    return sort {lc $a cmp lc $b} map $_->name, $self->get_all_Loci;
}

sub empty_Locus_cache {
    my( $self ) = @_;
    
    $self->{'_locus_cache'} = undef;
}

### Does not work
#sub rename_Locus {
#    my( $self, $old_name, $new_name ) = @_;
#    
#    $self->{'_locus_cache'}{$old_name} = $self->get_Locus($new_name);
#        
#    foreach my $name ($self->list_all_subseq_edit_window_names) {
#        my $sub = $self->get_SubSeq($name) or next;
#        my $locus = $sub->Locus or next;
#        if ($locus->name eq $old_name) {
#            warn "Renaming locus on SubSeq '$name'\n";
#            my $ec = $self->get_subseq_edit_window($name) or next;
#            $ec->update_Locus_from_XaceSeqChooser;
#        }
#    }
#    delete $self->{'_locus_cache'}{$old_name};
#}


#------------------------------------------------------------------------------------------

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
        #$xrem->send_command('save');
        $xrem->send_command('writeaccess -gain');
    } else {
        warn "no xwindow id: $xwid";
    }
}

sub xace_process_id {
    my( $self, $xace_process_id ) = @_;
    
    if ($xace_process_id) {
        $self->{'_xace_process_id'} = $xace_process_id;
    }
    return $self->{'_xace_process_id'};
}

sub launch_xace {
    my( $self ) = @_;
    
    $self->kill_xace;
    
    if (my $path = $self->ace_path) {
        if (my $pid = fork) {
            $self->xace_process_id($pid);
            $self->get_xwindow_id_from_readlock;
        }
        elsif (defined($pid)) {
            exec('xace', '-fmapcutcoords', $path);
        }
        else {
            confess "Error: can't fork : $!";
        }
    } else {
        warn "Error: ace_path not set";
    }
}

sub kill_xace {
    my( $self ) = @_;
    
    if (my $pid = $self->xace_process_id) {
        warn "Killing xace process '$pid'\n";
        kill 9, $pid;
    }
}

sub get_xwindow_id_from_readlock {
    my( $self ) = @_;
    
    local(*LOCK_DIR, *LOCK_FILE);

    my $pid  = $self->xace_process_id or confess "xace_process_id not set";
    my $path = $self->ace_path        or confess "ace_path not set";
    
    # Find the readlock file for the process we just launched
    my $lock_dir = "$path/database/readlocks";
    my( $lock_file );
    my $wait_seconds = 20;
    for (my $i = 0; $i < $wait_seconds; $i++, sleep 1) {
        opendir LOCK_DIR, $lock_dir or confess "Can't opendir '$lock_dir' : $!";
        ($lock_file) = grep /\.$pid$/, readdir LOCK_DIR;
        closedir LOCK_DIR;
        if ($lock_file) {
            $lock_file = "$lock_dir/$lock_file";
            last;
        }
    }
    unless ($lock_file) {
        warn "Can't find xace readlock file in '$lock_dir' for process '$pid' after waiting for $wait_seconds seconds\n";
        return 0;
    }
    
    my( $xwid );
    for (my $i = 0; $i < $wait_seconds; $i++, sleep 1) {
        # Extract the WindowID from the readlock file
        open LOCK_FILE, $lock_file or confess "Can't read '$lock_file' : $!";
        while (<LOCK_FILE>) {
            #warn "Looking at: $_";
            if (/WindowID: (\w+)/) {
                $xwid = $1;
                last;
            }
        }
        close LOCK_FILE;
        
        last if $xwid;
    }
    if ($xwid) {
        my $xrem = Hum::Ace::XaceRemote->new($xwid);
        $self->xace_remote($xrem);
        #$xrem->send_command('save');
        $xrem->send_command('writeaccess -gain');
        return 1;
    } else {
        warn "WindowID was not found in lock file - outdated version of xace?";
        return 0;
    }
}

sub populate_menus {
    my( $self ) = @_;
    
    my $menu_frame = $self->menu_bar
        or confess "No menu_bar";
    my $top = $menu_frame->toplevel;
    
    # File menu
    my $file = $self->make_menu('File');

    my $showing_zmap = 0;
    if($self->show_zmap) {
        # eval uses quotes here.  Tries to use the ZMap module.  If that fails
        # $INC{module_path} gets set, but must be deleted as we arrive here again.
        require MenuCanvasWindow::ZMapSeqChooser;
        my $zmap_launch_command = sub { $self->zMapLaunchZmap };
        $file->add('command',
                   -label          => 'Launch ZMap',
                   -command        => $zmap_launch_command,
                   -accelerator    => 'Ctrl+Z',
                   -underline      => 0,
                   );
        $top->bind('<Control-z>', $zmap_launch_command);
        $top->bind('<Control-Z>', $zmap_launch_command);
        $showing_zmap = 1;
    }

    # Launce xace
    my $xace_launch_command = sub { $self->launch_xace };
    $file->add('command',
        -label          => 'Launch Xace',
        -command        => $xace_launch_command,
        -accelerator    => 'Ctrl+L',
        -underline      => 0,
        );
    $top->bind('<Control-l>', $xace_launch_command);
    $top->bind('<Control-L>', $xace_launch_command);
     
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
    
    # Save annotations to otter
    my $save_command = sub {
        unless ($self->close_all_edit_windows) {
            $self->message('No saving because some editing windows are still open');
            return;
        }
        $self->save_data(1);
        };
    $file->add('command',
        -label          => 'Save',
        -command        => $save_command,
        -accelerator    => 'Ctrl+S',
        -underline      => 0,
        );
    $top->bind('<Control-s>', $save_command);
    $top->bind('<Control-S>', $save_command);
  
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
    
    ## Spawn dotter Ctrl .
    my $run_dotter_command = sub { $self->run_dotter };
    $file->add('command',
        -label          => 'Dotter fMap' . ($showing_zmap ? '/ZMap' : '').' hit',
        -hidemargin     => 1,
        -command        => $run_dotter_command,
        -accelerator    => 'Ctrl+.',
        -underline      => 0,
        );
    $top->bind('<Control-period>',  $run_dotter_command);
    $top->bind('<Control-greater>', $run_dotter_command);
    
    $file->add('separator');

    # Close window
    my $exit_command = sub {
        $self->exit_save_data or return;
        $self = undef;
        $menu_frame->toplevel->destroy;
        };
    $file->add('command',
        -label          => 'Close',
        -command        => $exit_command,
        -accelerator    => 'Ctrl+W',
        -underline      => 0,
        );
    $top->bind('<Control-w>', $exit_command);
    $top->bind('<Control-W>', $exit_command);
    $top->protocol('WM_DELETE_WINDOW', $exit_command);
    
    # Subseq menu
    my $subseq = $self->make_menu('SubSeq', 1);
    $self->subseq_menubutton($subseq->parent);
    
    # Edit subsequence
    my $edit_command = sub{
        $self->edit_subsequences;
        };
    $subseq->add('command',
        -label          => 'Edit',
        -command        => $edit_command,
        -accelerator    => 'Ctrl+E',
        -underline      => 0,
        );
    $top->bind('<Control-e>', $edit_command);
    $top->bind('<Control-E>', $edit_command);
    
    # Close all open subseq windows
    my $close_subseq_command = sub{
        $self->close_all_subseq_edit_windows;
        };
    $subseq->add('command',
        -label          => 'Close all',
        -command        => $close_subseq_command,
        -accelerator    => 'F4',
        -underline      => 0,
        );
    $top->bind('<F4>', $close_subseq_command);
    $top->bind('<F4>', $close_subseq_command);

    # Copy selected subseqs to holding pen
    my $copy_subseq = sub{
        $self->copy_selected_subseqs;
        };
    $subseq->add('command',
        -label          => 'Copy',
        -command        => $copy_subseq,
        -accelerator    => 'Ctrl+C',
        -underline      => 0,
        );
    $top->bind('<Control-c>', $copy_subseq);
    $top->bind('<Control-C>', $copy_subseq);

    # Paste selected subseqs, realigning them to the genomic sequence
    my $paste_subseq = sub{
        eval {
            $self->paste_selected_subseqs;
        };
        if ($@) {
            $self->exception_message($@);
        }
    };
    $subseq->add('command',
        -label          => 'Paste',
        -command        => $paste_subseq,
        -accelerator    => 'Ctrl+V',
        -underline      => 0,
        );
    $top->bind('<Control-v>', $paste_subseq);
    $top->bind('<Control-V>', $paste_subseq);
    
    #### Separator ####
    $subseq->add('separator');
    
    # New subsequence
    my $new_command = sub{
        $self->edit_new_subsequence;
        };
    $subseq->add('command',
        -label          => 'New',
        -command        => $new_command,
        -accelerator    => 'Ctrl+N',
        -underline      => 0,
        );
    $top->bind('<Control-n>', $new_command);
    $top->bind('<Control-N>', $new_command);
    
    # Make an variant of the current selected sequence
    my $variant_command = sub{
        $self->make_variant_subsequence;
        };
    $subseq->add('command',
        -label          => 'Variant',
        -command        => $variant_command,
        -accelerator    => 'Ctrl+I',
        -underline      => 2,
        );
    $top->bind('<Control-i>', $variant_command);
    $top->bind('<Control-I>', $variant_command);
    
    # Delete subsequence
    my $delete_command = sub {
        $self->delete_subsequences;
        };
    $subseq->add('command',
        -label          => 'Delete',
        -command        => $delete_command,
        -accelerator    => 'Ctrl+D',
        -underline      => 0,
        );
    $top->bind('<Control-d>', $delete_command);
    $top->bind('<Control-D>', $delete_command);

    $subseq->bind('<Destroy>', sub{
        $self = undef;
        });

    ### Unimplemented methods
    #$subseq->add('command',
    #    -label          => 'Merge',
    #    -command        => sub{ warn "Called Merge" },
    #    -accelerator    => 'Ctrl+M',
    #    -underline      => 0,
    #    -state          => 'disabled',
    #    );
    #$subseq->add('command',
    #    -label          => 'AutoMerge',
    #    -command        => sub{ warn "Called AutoMerge" },
    #    -accelerator    => 'Ctrl+U',
    #    -underline      => 0,
    #    -state          => 'disabled',
    #    );
    #
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
    
    # Object won't get DESTROY'd without:
    $canvas->Tk::bind('<Destroy>', sub{
        #cluck "Dealing with <Destroy> call";
        $self = undef;
        });
}

## needs to be called when drawing the clone_sequences (clone sequence details not present when other menus are created)
sub populate_Features_menu {
    my ($self) = @_;
    
    my $menu_frame = $self->menu_bar
            or confess 'No menu Bar';

    my $gf_menu = $self->make_menu("Features");
    $gf_menu->add( 'command' ,
                -label => $self->slice_name,    
                -command => sub { $self->launch_GenomicFeatures },
    );
    $gf_menu->bind('<Destroy>', sub{ $self = undef });
}

sub GenomicFeatures {
    my ($self, $gfs) = @_ ;

    if(defined($gfs)){
        $self->{_gfs} = $gfs;
        weaken($self->{_gfs});
    }
    return $self->{_gfs};
}

sub launch_GenomicFeatures {
    my( $self ) = @_;
    eval {
        if(my $gfs = $self->GenomicFeatures()) {

            my $gfw = $gfs->top_window();
            $gfw->deiconify;
            $gfw->raise;
        } else {
            my $clone = $self->get_CloneSeq;

            my $gfw = $self->canvas->Toplevel;

            $gfs = MenuCanvasWindow::GenomicFeatures->new($gfw);
            $self->GenomicFeatures($gfs);
            $gfs->XaceSeqChooser($self);
            $gfs->write_access($self->write_access());
            $gfs->initialize;
        }
    };
    if ($@) {
        $self->exception_message("Error creating GenomicFeatures window", $@);
    }
}

sub close_GenomicFeatures {
    my $self = shift @_;

    if(my $gfs = $self->GenomicFeatures()) {
        $gfs->try2save_and_quit();
    }
}


{
    my( @holding_pen );

    sub copy_selected_subseqs {
        my( $self ) = @_;
        
        # Empty holding pen
        @holding_pen = ();
        
        my @select = $self->list_selected_subseq_names;
        unless (@select) {
            $self->message('Nothing selected');
            return;
        }
        foreach my $name (@select) {
            my $sub = $self->get_SubSeq($name)->clone;
            $sub->is_archival(0);
            push(@holding_pen, $sub);
        }
    }

    sub paste_selected_subseqs {
        my( $self ) = @_;
        
        unless (@holding_pen) {
            $self->message('No SubSequences on clipboard');
            return;
        }
        
        unless ($self->current_state eq 'subseq') {
            $self->message('Can only paste when in SubSequence view');
            return;
        }
        
        my $clone = $self->get_CloneSeq;
        
        # The ExonLoacator finds exons in a genomic sequence
        my $finder = Hum::Analysis::Factory::ExonLocator->new;
        $finder->genomic_Sequence($clone->Sequence);

        my( @msg, @new_subseq, $i );
        foreach my $sub (@holding_pen) {
            my $name = $sub->name;
            my $exon_seq = $sub->exon_Sequence_array;
            my $fs = $finder->find_best_Feature_set($exon_seq);
            my @exons = $sub->get_all_Exons;
            my( $strand, @new_exons, $done_msg );
            for (my $i = 0; $i < @exons; $i++) {
                my $feat = $fs->[$i] or next;
                my $ex = Hum::Ace::Exon->new;
                $ex->start($feat->seq_start);
                $ex->end($feat->seq_end);
                $strand ||= $feat->seq_strand;
                push(@new_exons, $ex);
            }
            
            if (@new_exons) {
                my $new = $sub->clone;
                my( $temp_name );
                do {
                    $temp_name = sprintf "TEMP-%03d", ++$i;
                } while ($self->get_SubSeq($temp_name));
                #my $temp_name = sprintf "TEMP-%03d", ++$i;
                $new->name($temp_name);
                $new->strand($strand);
                $new->replace_all_Exons(@new_exons);
                $new->clone_Sequence($clone->Sequence);
                $clone->add_SubSeq($new);
                if ($sub->translation_region_is_set) {
                    eval {
                        $new->set_translation_region_from_cds_coords($sub->cds_coords);
                    };
                    if ($@) {
                        push(@msg, "Failed to set translation region - check translation of '$temp_name'");
                        $new->translation_region($new->start, $new->end);
                    }
                }
                $new->Locus($self->get_Locus($sub->Locus->name));
                ### set locus gene_type_prefix() here ?
                $self->add_SubSeq($new);
                push(@new_subseq, $new);
                print STDERR $new->ace_string;
            } else {
                $self->message("Got zero exons from realigning '$name'");
            }
        }
        $self->draw_subseq_list;
        $self->highlight_by_name('subseq', map $_->name, @new_subseq);
        $self->message(@msg) if @msg;
        foreach my $new (@new_subseq) {
            $self->make_exoncanvas_edit_window($new);
        }
        $self->fix_window_min_max_sizes;
    }
}

sub exit_save_data {
    my( $self ) = @_;

    my $ace = $self->AceDatabase;
    unless ($self->write_access) {
        $ace->error_flag(0);
        $self->close_GenomicFeatures;
        $self->kill_xace;
        return 1;
    }
    
    $self->close_all_edit_windows or return;
    
    # Ask the user if any changes should be saved
    my $dialog = $self->top_window()->Dialog(
        -title          => 'Otter save?',
        -bitmap         => 'question',
        -text           => "Save any changes to otter server?",
        -default_button => 'Yes',
        -buttons        => [qw{ Yes No Cancel }],
        );
    my $ans = $dialog->Show;

    if ($ans eq 'Cancel') {
        return;
    }
    elsif ($ans eq 'Yes') {
        # Return false if there is a problem saving
        $self->save_data or return;
    }

    # Will not want xace any more
    $self->kill_xace;
    
    # Unlock and cleanup (lace dir gets
    # removed by AceDatabase->DESTROY)

    # no need to unlock this gets done by 
    # AceDatabase->DESTROY now.

    # sequenceNotes clean up and lock refresh.
    
    $ace->error_flag(0);
    
    return 1;
}

sub close_all_edit_windows {
    my( $self ) = @_;
    
    $self->close_all_subseq_edit_windows or return;
    $self->close_GenomicFeatures;
    return 1;
}

sub save_data {
    my( $self, $update_ace ) = @_;
    ## update_ace should be true unless object is exiting 
    ## i.e. when called from ->exit_save_data()
    #warn "SAVING DATA";

    if (my $xr = $self->xace_remote) {
        
        #warn "XACE SAVE";
        # This will fail if xace has been
        # exited, so we ignore error.
        eval{ $xr->save; };
    }

    unless ($self->write_access) {
        warn "Read only session - not saving\n";
        return 1;   # Can't save - but is OK
    }
    my $top = $self->top_window();

    $top->Busy;

    eval{
        my $ace_data = $self->AceDatabase->save_all_slices;
        ## update_ace should be true unless this object is exiting
        if($update_ace && ref($ace_data) eq 'SCALAR'){
            $self->launch_xace;
            $self->update_ace_display($$ace_data);
            # resync here!
            $self->resync_with_db; # probably better to create a key event
            ### Restart Zmap
        }
    };
    my $err = $@;
    
    $top->Unbusy;
    
    if ($err) {
        $self->exception_message($err, 'Error saving to otter');
        return 0;
    } else {
        return 1;
    }
}

sub edit_double_clicked {
    my( $self ) = @_;
    
    return unless $self->list_selected;
    
    my $canvas = $self->canvas;
    $canvas->Busy;
    $self->edit_subsequences;
    $canvas->Unbusy;
}

sub left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;

    return if $self->delete_message;

    $self->deselect_all;
    if (my ($obj) = $canvas->find('withtag', 'current')) {
        $self->highlight($obj);
    }
}

sub shift_left_button_handler {
    my( $self, $canvas, $x, $y ) = @_;

    return if $self->delete_message;

    if (my ($obj) = $canvas->find('withtag', 'current')) {
        if ($self->is_selected($obj)) {
            $self->remove_selected($obj);
        } else {
            $self->highlight($obj);
        }
    }
}

sub _make_search {
    my ($self) = @_;

    my $top = $self->top_window();
    my $search_frame = $top->Frame();
    $search_frame->pack(-side => 'top');
    
    #my $label = $search_frame->Label(-text => 'Search text:');
    #$label->pack(-side => 'left');
    #$search_frame->Frame(-width => 6)->pack(-side => 'left');
    
    my $search_box = $search_frame->Entry(
        -width => 22,
        );
    $search_box->pack(-side => 'left');
    
    $search_frame->Frame(-width => 6)->pack(-side => 'left');
    
    ## Is hunting in CanvasWindow?
    my $hunter = sub{
	$top->Busy;
	$self->hunt_for_Entry_text($search_box);
	$top->Unbusy;
    };
    my $button = $search_frame->Button(
         -text      => 'Find',
         -command   => $hunter,
         -underline => 0,
         )->pack(-side => 'left');

    my $clear_command = sub {
        $search_box->delete(0, 'end');
        };
    my $clear = $search_frame->Button(
        -text      => 'Clear',
        -command   => $clear_command,
        -underline => 2,
        )->pack(-side => 'left');
    $top->bind('<Control-e>',   $clear_command);
    $top->bind('<Control-E>',   $clear_command);
    
    $search_box->bind('<Return>',   $hunter);
    $search_box->bind('<KP_Enter>', $hunter);
    $top->bind('<Control-f>',       $hunter);
    $top->bind('<Control-F>',       $hunter);

    $button->bind('<Destroy>', sub{
        $self = undef;
        });
}

sub hunt_for_Entry_text{
    my ($self, $entry) = @_; 
#   Finds the text given in the supplied Entry in $self->canvas
#   Very similar to hunt_for_selection in SequenceNotes.pm
#   potential for refactoring...
    my $canvas = $self->canvas;
    my( $query_str, $regex );
    eval{
	$query_str = $entry->get();
	$query_str =~ s{(\W)}{\\$1}g;
	$regex =  qr/($query_str)/i;
    };
    return unless $query_str;
#    warn $query_str;
#    warn $regex;
    $canvas->delete('msg');
    $self->deselect_all();
    my @all_text_obj = $canvas->find('withtag', 'searchable');
    unless (@all_text_obj) {
        ### Sometimes a weird error occurs where the first call to find
        ### doesn't return anything - warn user if this happens.
        $self->message('No searchable text on canvas - is it empty?');
        return;
    }

    my $found = 0;
    foreach my $obj (@all_text_obj) {
        my $text = $canvas->itemcget($obj, 'text');
#        warn "matching $text against $regex\n";
        if (my ($hit) = $text =~ /$regex/) {
            $found = $obj;
	    $self->highlight($obj);
        }
    }
    unless ($found) {
        $self->message("Can't find '$query_str'");
        return;
    }
}

sub ace_handle {
    my( $self ) = @_;
    
    return $self->AceDatabase->aceperl_db_handle;
}

sub ace_path {
    my( $self ) = @_;
    
    return $self->AceDatabase->home;
}

sub resync_with_db {
    my( $self ) = @_;
    
    
    unless ($self->close_all_edit_windows) {
        $self->message("All editor windows must be closed before a ReSync");
        return;
    }
    
    $self->canvas->Busy(
        -recurse => 0,
        );

    $self->AceDatabase->ace_server->restart_server;
    
    $self->empty_CloneSeq_cache;
    $self->empty_SubSeq_cache;
    $self->empty_Locus_cache;
    
    # Redisplay
    $self->draw_subseq_list;
    
    $self->canvas->Unbusy;
}

sub max_seq_list_length {
    return 1000;
}

sub slice_name {
    my( $self ) = @_;
    
    my $slice_name;
    unless ($slice_name = $self->{'_slice_name'}) {
        my $adbh = $self->ace_handle;
        my @slice_list = map $_->name,
            $adbh->fetch(Assembly => '*');
        if (@slice_list > 1) {
            $self->message("Error: more than 1 assembly in database:", @slice_list);
            return;
        }
        $slice_name = $self->{'_slice_name'} = $slice_list[0];
    }
    return $slice_name;
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
    my( $self, $zmap ) = @_;
    
    my @sub_names = $self->list_selected_subseq_names;
    my( @subseq );
    foreach my $sn (@sub_names) {
        my $sub = $self->get_SubSeq($sn);
        push(@subseq, $sub);
    }

    my( @ints, $most_3prime );
    if (@subseq) {
        # Find 3' most coordinate in subsequences
        foreach my $sub (@subseq) {
            my( $this_3prime );
            if ($sub->strand == 1) {
                $this_3prime = $sub->end;
                if ($most_3prime) {
                    next unless $this_3prime > $most_3prime;
                }
            } else {
                $this_3prime = $sub->start;
                if ($most_3prime) {
                    next unless $this_3prime < $most_3prime;
                }
            }
            $most_3prime = $this_3prime;
        }
    } else {
        # Get 3' most coordinate from those on clipboard
        # (feature highlighted in xace fMap)
        @ints = $self->integers_from_clipboard;
        foreach my $i (@ints) {
            $most_3prime ||= $i;
            $most_3prime = $i if $i > $most_3prime;
        }
    }
    
    my $slice = $self->get_CloneSeq;
    my $region_name = $most_3prime
        ? $slice->clone_name_overlapping($most_3prime)
        : $slice->ace_name;
    #warn "Looking for clone overlapping '$most_3prime' in '$clone_name' found '$region_name'";
    
    # Trim sequence version from accession if clone_name ends .SV
    $region_name =~ s/\.\d+$//;

    my $regex = qr{^(?:[^:]+:)?$region_name\.(\d+)}; # qr is a Perl 5.6 feature
    my $max = 0;
    foreach my $sub ($slice->get_all_SubSeqs) {
        my ($n) = $sub->name =~ /$regex/;
        if ($n and $n > $max) {
            $max = $n;
        }
    }
    $max++;
    
    
    # Now get the maximum locus number for this root
    my $prefix = Bio::Otter::Lace::Defaults::fetch_gene_type_prefix() || '';
    my $loc_name = $prefix ? "$prefix:$region_name.$max" : "$region_name.$max";
    my $locus = $self->get_Locus($loc_name);
    $locus->gene_type_prefix($prefix);

    my $seq_name = "$loc_name-001";
    
    # Check we don't already have a sequence of this name
    if ($self->get_SubSeq($seq_name)) {
        # Should be impossible, I hope!
        $self->message("Tried to make new SubSequence name but already have SubSeq named '$seq_name'");
        return;
    }

    #warn "Making '$seq_name'\n";
    my( $new );
    if (@subseq) {
        $new = $subseq[0]->clone;
        for (my $i = 1; $i < @subseq; $i++) {
            my $extra_sub = $subseq[$i]->clone;
            foreach my $ex ($extra_sub->get_all_Exons) {
                $new->add_Exon($ex);
            }
        }
    }
    else {
        $new = Hum::Ace::SubSeq->new;
        $new->strand(1);
        $new->clone_Sequence($slice->Sequence);
        
        if (@ints > 1) {
            # Make exons from coordinates from clipboard
            for (my $i = 0; $i < @ints; $i += 2) {
                my $start = $ints[$i];
                my $end   = $ints[$i + 1] or last;
                if ($start > $end) {
                    ($start, $end) = ($end, $start);
                    $new->strand(-1);
                }
                my $ex = $new->new_Exon;
                $ex->start($start);
                $ex->end  ($end);
            }
        } else {
            # Need to have at least 1 exon
            my $ex = $new->new_Exon;
            $ex->start(1);
            $ex->end  (2);
        }
    }
    $new->name($seq_name);
    $new->Locus($locus);
    $new->empty_evidence_hash;
    $new->empty_remarks;
    $new->empty_annotation_remarks;
    my $gm = $self->get_default_mutable_GeneMethod or confess "No default mutable GeneMethod";
    

    ## problem where translation was not being set on newly created 'Coding' SubSeq's
    if ($gm->transcript_type eq 'coding'){        
        $new->translation_region( $new->start , $new->end) ;
    }
    
    $new->GeneMethod($gm);

    $slice->add_SubSeq($new);

    $self->add_SubSeq($new);
    $self->do_subseq_display;
    $self->highlight_by_name('subseq', $seq_name);
    if($zmap){
        $self->zMap_make_exoncanvas_edit_window($new);
    }else{
        $self->make_exoncanvas_edit_window($new);
    }
    
    $self->fix_window_min_max_sizes;
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
        if ($sub->GeneMethod->mutable) {
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
    my $dialog = $self->top_window()->Dialog(
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
    $xr->send_command('gif ; seqrecalc');
    
    # Remove from our objects
    foreach my $sub (@to_die) {
        $self->delete_SubSeq($sub);
    }
    
    $self->draw_subseq_list;
}

sub make_variant_subsequence {
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
        $self->message("Can't make a variant from more than one selected sequence");
        return;
    }
    my $name = $sub_names[0];
    my $sub = $self->get_SubSeq($name);
    my $clone = $self->get_CloneSeq($sub->clone_Sequence->name);
    
    # Work out a name for the new variant
    my $var_name = $name;
    if ($var_name =~ s/-(\d{3,})$//) {
        my $root = $var_name;

        # Now get the maximum variant number for this root
        my $regex = qr{^$root-(\d{3,})$};
        my $max = 0;
        foreach my $sub ($clone->get_all_SubSeqs) {
            my ($n) = $sub->name =~ /$regex/;
            if ($n and $n > $max) {
                $max = $n;
            }
        }

        $var_name = sprintf "%s-%03d", $root, $max + 1;
    
        # Check we don't already have the variant we are trying to create
        if ($self->get_SubSeq($var_name)) {
            $self->message("Tried to create variant '$var_name', but it already exists! (Should be impossible)");
            return;
        }
    } else {
        $self->message(
            "SubSequence name '$name' is not in the expected format " .
            "(ending with a dash followed by three or more digits).",
            "Perhaps you want to use the \"New\" funtion instead?",
            );
        return;
    }
    
    # Make the variant
    my $var = $sub->clone;
    $var->empty_evidence_hash;
    $var->empty_remarks;
    $var->empty_annotation_remarks;
    $var->name($var_name);
    $self->add_SubSeq($var);
    $clone->add_SubSeq($var);
    
    $self->draw_subseq_list;
    $self->highlight_by_name('subseq', $name, $var_name);
    $self->edit_subsequences($var_name);
}

sub make_exoncanvas_edit_window {
    my( $self, $sub ) = @_;
    
    my $sub_name = $sub->name;
#    warn "subsequence-name $sub_name " ;
#    warn "locus " . $sub->Locus->name ;
    my $canvas = $self->canvas;
    
    # Make a new window
    my $top = $canvas->Toplevel;
    
    # Make new MenuCanvasWindow::ExonCanvas object and initialize
    my $ec = MenuCanvasWindow::ExonCanvas->new($top, 345, 50);
    $ec->name($sub_name);
    $ec->XaceSeqChooser($self);
    $ec->SubSeq($sub);
    $ec->initialize;
    
    $self->save_subseq_edit_window($sub_name, $ec);
    
    return $ec;
}

sub raise_subseq_edit_window {
    my( $self, $name ) = @_;
    
    confess "no name given" unless $name;
    
    if (my $ec = $self->get_subseq_edit_window($name)) {
        my $top = $ec->canvas->toplevel;
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
    my( $self, $name, $ec ) = @_;
    
    $self->{'_subseq_edit_window'}{$name} = $ec;
    weaken($self->{'_subseq_edit_window'}{$name});
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

sub close_all_subseq_edit_windows {
    my( $self ) = @_;

    foreach my $name ($self->list_all_subseq_edit_window_names) {
        my $ec = $self->get_subseq_edit_window($name) or next;
        $ec->window_close or return 0;
    }
    
    return 1;
}

sub update_all_locus_edit_fields {
    my( $self, $locus_name ) = @_;
    
    foreach my $name ($self->list_all_subseq_edit_window_names) {
        warn "Looking at: '$name'";
        my $sub = $self->get_SubSeq($name) or next;
        my $locus = $sub->Locus or next;
        if ($locus->name eq $locus_name) {
            warn "Updating '$name'";
            my $ec = $self->get_subseq_edit_window($name) or next;
            $ec->update_Locus_from_XaceSeqChooser;
        }
    }
}

### KEEP ###
sub draw_subseq_list {
    my( $self, @selected_clones ) = @_;
    
    my $canvas = $self->canvas;
    
    my( @subseq );
    my $counter = 1;
    foreach my $clust ($self->get_all_Subseq_clusters) {
        push(@subseq, "") if @subseq;
        push(@subseq, map($_->name, @$clust));
    }
    
    $self->draw_sequence_list('subseq', @subseq);
    $self->subseq_menubutton->configure(-state => 'normal');

}

sub get_all_Subseq_clusters {
    my( $self ) = @_;
    
    my $clone = $self->get_CloneSeq;
    my @subseq = sort {
           $a->start  <=> $b->start
        || $a->end    <=> $b->end
        || $a->strand <=> $b->strand
        } $clone->get_all_SubSeqs;
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
    
    foreach my $c (@clust) {
        $c = [sort {$a->name cmp $b->name} @$c];
    }
    
    return sort {$a->[0]->start <=> $b->[0]->start} @clust;
}

sub get_CloneSeq {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    
    my( $clone );
    unless ($clone = $self->{'_clone_sequence'}) {
        use Time::HiRes 'gettimeofday';
        my $before = gettimeofday();
        $canvas->Busy(
            -recurse => 0,
            );
        $clone = $self->express_clone_and_subseq_fetch;
        my $after  = gettimeofday();
        $canvas->Unbusy;
        printf "Express fetch for '%s' took %4.3f\n", $self->slice_name, $after - $before;
        $self->{'_clone_sequence'} = $clone;
    }
    return $clone;
}

sub empty_CloneSeq_cache {
    my( $self ) = @_;
    
    $self->{'_clone_sequence'} = undef;
}

sub express_clone_and_subseq_fetch {
    my( $self ) = @_;
    
    my $clone_name = $self->slice_name;
    my $ace = $self->ace_handle;
    my( $clone );
    eval {
        $clone = Hum::Ace::CloneSeq
            ->new_from_name_and_db_handle($clone_name, $ace);
    };
    if ($clone) {
        $self->exception_message($@) if $@;
    } else {
        $self->exception_message($@, "Can't fetch CloneSeq '$clone_name'");
        return;
    }
    
    foreach my $sub ($clone->get_all_SubSeqs) {
        $self->add_SubSeq($sub);
            
	if (my $s_meth = $sub->GeneMethod) {
            my $meth = $self->get_GeneMethod($s_meth->name);
            $sub->GeneMethod($meth);
        }

        if (my $s_loc = $sub->Locus) {
            my $locus = $self->get_Locus($s_loc);
            $sub->Locus($locus);
        }
    }
    return $clone;
}

sub replace_SubSeq {
    my( $self, $sub, $old_name ) = @_;
    
    my $sub_name = $sub->name;
    $old_name ||= $sub_name;
    my $clone = $self->get_CloneSeq;
    $clone->replace_SubSeq($sub, $old_name);
    if ($sub_name ne $old_name) {
        $self->{'_subsequence_cache'}{$old_name} = undef;
        $self->rename_subseq_edit_window($old_name, $sub_name);
    }
    $self->{'_subsequence_cache'}{$sub_name} = $sub;

    my $locus = $sub->Locus;
    if (my $prev_name = $locus->drop_previous_name) {
        warn "Unsetting otter_id for locus '$prev_name'\n";
        $self->get_Locus($prev_name)->drop_otter_id;
    }
    $self->set_Locus($locus);

    ### Update all subseq edit windows
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
    $self->get_CloneSeq->delete_SubSeq($name);
    
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

sub list_all_SubSeq_names {
    my ($self) = @_ ;

    if (my $sub_hash = $self->{'_subsequence_cache'}) {
        return keys %$sub_hash;
    } else {
        return;
    }
}

sub empty_SubSeq_cache {
    my( $self ) = @_;
    
    $self->{'_subsequence_cache'} = undef;
}

sub draw_sequence_list {
    my( $self, $tag, @slist ) = @_;

    # Work out number of rows to keep chooser
    # window roughly square.  Also a lower and
    # an upper limit of 20 and 40 rows.  
    my $total_name_length = 0;
    foreach my $name (@slist) {
        $total_name_length += length($name);
    }
    my $rows = int sqrt($total_name_length);
    if ($rows < 20) {
        $rows = 20;
    }
    elsif ($rows > 40) {
        $rows = 40;
    }

    my $canvas = $self->canvas;
    my $font = $self->font;
    my $size = $self->font_size;
    my $pad  = int($size / 6);
    my $half = int($size / 2);
    
    # Delete everything apart from messages
    $canvas->delete('all&&!msg');

    my $x = 0;
    my $y = 0;
    for (my $i = 0; $i < @slist; $i++) {
        if (my $text = $slist[$i]) {

            my $style = 'bold';
            my $color = 'black';
            
            # Special rules for SubSequences
            if ($tag eq 'subseq') {
                my $sub = $self->get_SubSeq($text);
                if ($sub->is_mutable) {
                    $color = 'black';
                }
                elsif (my $locus = $sub->Locus) {
                    $color = '#999999';
                }
                else {
                    $style = 'normal';
                }
            }

	        $canvas->createText(
		        $x, $y,
		        -anchor     => 'nw',
		        -text       => $text,
		        -font       => [$font, $size, $style],
		        -tags       => [$tag, 'searchable'],
		        -fill       => $color,
		        );
        }
        
        if (($i + 1) % $rows) {
            $y += $size + $pad;
        } else {
            $y = 0;
            my $x_max = ($canvas->bbox($tag))[2];
            $x = $x_max + ($size * 2);
        }
    }
    
    # Raise messages above everything else
    eval{
        $canvas->raise('msg', $tag);
    };
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

      # HACK
      # above format NOT returnd by xwininfo on Sun OS 5.7:
      #  tace version:
      #  ACEDB 4_9r,  build dir: RELEASE.2003_05_01
      # 2 lines before modified to support xace at RIKEN

        # BEFORE: if (/Window id: (\w+) "([^"]+)/) {
        if (/Window id: (\w+) "([^"]+)/ || /Window id: (\w+)/) {
            my $id   = $1;
            my $name = $2;
	    # BEFORE: if ($name =~ /^ACEDB/){
            if ($name =~ /^ACEDB/ || $name eq '') {
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

sub run_dotter {
    my( $self ) = @_;
    
    my $dw = $self->{'_dotter_window'};
    unless ($dw) {
        my $parent = $self->top_window();
        my $top = $parent->Toplevel(-title => 'run dotter');
        $top->transient($parent);
        $dw = CanvasWindow::DotterWindow->new($top);
        $dw->initialise;
        $self->{'_dotter_window'} = $dw;
    }
    $dw->update_from_XaceSeqChooser($self);
    
    return 1;
}

sub show_zmap {
    my $self = shift @_;

    return Bio::Otter::Lace::Defaults::option_from_array(['client', 'show_zmap']) || 0;
}

sub isZMap{
    my($self, $x_or_z) = @_;
    if(defined($x_or_z)){
        $self->{'xace_or_zmap'} = $x_or_z;
        $self->__hasEverZMap(1) if $x_or_z;
    }
    return ($self->{'xace_or_zmap'} ? 1 : 0);
}
sub __hasEverZMap{
    my($self, $zmapped) = @_;
    $self->{'zmapped'} = $zmapped if defined($zmapped);
    return ($self->{'zmapped'} ? 1 : 0);
}

sub DESTROY {
    my( $self ) = @_;

    if($self->__hasEverZMap){
        $self->zMapKillZmap() if $self->can('zMapKillZmap');
        ZMap::ConnectUtils::flush_bad_windows();
        delete $self->{'_SGIF_LOCAL_SERVER'}; # shutdown server
    }

    # need to undef AceDatabase for it's clean up.
    # warn "AceDatabase->unlock should now happen\n";
    ### Don't need this!
    ###delete $self->{'_AceDatabase'}; # unlock will now happen
    # warn "AceDatabase->unlock should have happened\n";
    if (my $sn = $self->SequenceNotes){
        # then refresh locks
        # warn "lock refresh should now happen\n";
        $sn->refresh_column(7) ; ## locks column
        # warn "lock refresh should have happened\n";
        # need to clean up the sequenceNotes reference
        ### No you don't!
        ###delete $self->{'_sequence_notes'} ;
    }

    if ($self->isZMap){
        warn "Destroying ZmapSeqChooser for ", $self->ace_path, "\n";
    }else{
        warn "Destroying XaceSeqChooser for ", $self->ace_path, "\n";
    }
}

1;

__END__

=head1 NAME - MenuCanvasWindow::XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

