
### MenuCanvasWindow::XaceSeqChooser

package MenuCanvasWindow::XaceSeqChooser;

use strict;
use 5.006_001;  # For qr support
use Carp qw{ cluck confess };
use Tk::Dialog;
use Hum::Ace::SubSeq;
use Hum::Ace::Locus;
use Hum::Ace::GeneMethod;
use Hum::Ace::XaceRemote;
use Hum::Ace::DotterLauncher;
use Hum::Sequence::DNA;
use Hum::Ace;
use Data::Dumper;

use base 'MenuCanvasWindow';
use MenuCanvasWindow::ExonCanvas;
use CanvasWindow::DotterWindow;
use CanvasWindow::PolyAWindow;
use CanvasWindow::LocusWindow;
use Bio::Otter::Lace::Defaults;

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
        $self->ace_path($AceDatabase->home);
    }
    return $self->{'_AceDatabase'};
}

sub SequenceNotes{
    my ($self , $sn) = @_ ;
    
    if ($sn){
        $self->{'_sequence_notes'} = $sn ;
    }
    return $self->{'_sequence_notes'} ;
}

sub initialize {
    my( $self ) = @_;
    
    # take GeneMethods from Defaults.pm file
    Bio::Otter::Lace::Defaults->set_known_GeneMethods($self) ;
    
    $self->draw_clone_list;
    
    ## populate polyA menu here
    ## wasn't possible to do it at the same time as other menus, as AceDB object wasnt added at that point.    
    $self->populate_polyA_menu();
    
    $self->_make_search;
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

sub clone_sub_switch_var {
    my( $self, $switch_ref ) = @_;
    
    if ($switch_ref) {
        $self->{'_clone_sub_switch_var'} = $switch_ref;
    }
    return $self->{'_clone_sub_switch_var'};
}

# this method has been moved to Bio::Otter::Lace::Defaults.pm
# but this has been left for backwards compatibility
sub set_known_GeneMethods{
    my  ($self) = @_ ;
    Bio::Otter::Lace::Defaults->set_known_GeneMethods($self) ;
}

sub fetch_GeneMethod {
    my( $self, $name ) = @_;
    
    confess "Missing name argument" unless $name;
    my $ace = $self->ace_handle->fetch(Method => $name);
    my( $meth );
    if ($ace) {
        $meth = Hum::Ace::GeneMethod->new_from_ace($ace);
    } else {
        warn "Making method not in db: '$name'\n";
        $meth = Hum::Ace::GeneMethod->new;
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
    return grep $_->is_mutable, @$list;
}

sub get_default_mutable_GeneMethod {
    my( $self ) = @_;
   
    my @possible = grep $_->is_coding, $self->get_all_mutable_GeneMethods;
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

 # called from ExonCanvas. $state should be either 'new' or 'edit'
sub show_LocusWindow{
    my ($self , $exon_canv , $state) = @_ ;  
    
    my $locus ;
    $locus = $exon_canv->SubSeq->Locus ;  
  
    my $top;
    my $window ;

    $window = $self->{'_locus_window_cache'}{$locus};
        
    unless($window){
       
        print STDERR "creating LocusWindow from Xace\n" ;
        $top = $self->canvas->Toplevel(-width => 500);
       
        $window = CanvasWindow::LocusWindow->new($top);        
        $self->{'_locus_window_cache'}{$locus} = $window;
        $window->initialize; 
    
    }
    $window->last_exon_canvas($exon_canv);    
    $window->show($state); 
}

sub close_all_LocusWindows { 
    my ($self) = @_ ;

    $self->{'_locus_window_cache'} = undef ;
}

sub get_all_locus_windows{
    my ($self) = @_ ;
    
    my @array ;
    my %hash = %{$self->{'_locus_window_cache'}}  ;  
    while (my ($key , $value) = each (%hash)){
        push (@array , $value);
    }
    return @array ;
}

sub add_new_Locus{
    my ($self , $locus) = @_ ;
    
    my $name = $locus->name;
    if ($self->{'_locus_cache'}{$name} ){
        $self->message("The new locus name has already been assigned, please choose another");
        return 0;
    }
    else{
        $self->{'_locus_cache'}{$name} = $locus ;  
        return 1;
    }
}

sub remove_Locus_if_not_in_use{
    my ($self , $locus_name) = @_ ;   
    my %subseq_hash = %{$self->get_stored_SubSeq_hash()} ;   
    while (my ($key , $SubSeq ) = each (%subseq_hash) ){
        # dont delete locus if another subseq is using it
        my $locus = $SubSeq->Locus || next ;
        if ( $locus->name eq  $locus_name  ) {
            return;
        }
    }         
    #locus is not used anywhere else - get rid of it (or it will cause other problems)
    $self->remove_Locus($locus_name);
    
}

sub remove_Locus{
    my ($self , $locus_name) = @_;
    if ($self->{'_locus_cache'}{$locus_name}){
        #print STDERR "removing " . $locus_name;
        # remove all associated windows first
        my $locus = $self->get_Locus($locus_name); 
        delete ($self->{'_locus_window_cache'}{$locus}) ;
        delete ($self->{'_locus_cache'}{$locus_name});      
    }
    else{
        print STDERR "No Locus with name $locus_name to be removed" ;
    }
}


sub rename_loci{
    my ($self , $old_name , $new_name ) = @_ ; 
    
    #warn "renaming locus '$old_name' to '$new_name'\n";
    my $locus = $self->get_Locus($old_name);
    $self->remove_Locus($old_name) ; # otherwise we have two hash keys for the same locus.
    $locus->name($new_name); 
    $self->add_new_Locus($locus) ;
    
    my $ace = $locus->ace_string($old_name);  
    
    foreach my $name ($self->list_all_subseq_edit_window_names) {
        my $top = $self->get_subseq_edit_window($name) or next;
        $top->deiconify;
        $top->raise;
        $top->update;
        $top->focus;
        $top->eventGenerate('<<refresh_locus_display>>');
    } 
    $self->update_ace_display($ace);   
}


# go through all the SubSeq objects replace the locus if  it is the selected one ($removable_name)
# add data to .ace file for each locus changed. Update AceDb with this file.
sub merge_loci {
    my ($self , $stable_name , $removable_name) = @_ ;
    
    my $stable_locus = $self->get_Locus( $stable_name);
    my $removable_locus = $self->get_Locus($removable_name) ;  
    $self->replace_loci($removable_locus , $stable_locus);
}

sub replace_loci{
    my ($self , $old , $new) = @_ ;

    my %subseq_hash = %{$self->get_stored_SubSeq_hash()};
    my $ace = '';   
    while (my ($name, $SubSeq) = each(%subseq_hash)){   
        if (($SubSeq->Locus || next ) == $old){
            $SubSeq->Locus($new) ; 
            $ace .= $SubSeq->ace_string ;              
            $SubSeq->is_archival(1);
#            warn "updating ace db for " . $SubSeq->name;  
        }    
    }
    my $result = $self->update_ace_display($ace);  
    unless ($result == 0){
        $self->remove_Locus($old->name);
    }
}



sub update_ace_display{
    my ($self , $ace) = @_ ;
    
    
    my $xr = $self->xace_remote  || $self->open_xace_dialogue;
    
    print STDERR "Sending:\n$ace";
    if ($xr) {
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
    
    my $answer = $self->canvas->toplevel()->messageBox(-title => 'Please Reply', 
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

sub get_all_Loci {
    my( $self ) = @_;    
    my $lc = $self->{'_locus_cache'};
    return values %$lc;
}

sub list_Locus_names {
    my( $self ) = @_;    
    return sort {lc $a cmp lc $b} map $_->name, $self->get_all_Loci;
}

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
    
    ## Respawn
    #$file->add('command',
    #    -label          => 'Restart',
    #    -hidemargin     => 1,
    #    -command        => sub { $self->command_line_restart },
    #    #-accelerator    => 'Ctrl+R',
    #    #-underline      => 0,
    #    );
    
    ## Spawn dotter Ctrl .
    my $run_dotter_command = sub { $self->run_dotter };
    $file->add('command',
        -label          => 'Dotter fMap hit',
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
    my $subseq = $self->make_menu('SubSeq', 1);
    $self->subseq_menubutton($subseq->parent);
    
    # Edit subsequence
    my $edit_command = sub{
        return unless $self->current_state eq 'subseq';
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
    
    my $close_subseq_command = sub{
        return unless $self->current_state eq 'subseq';
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

    
    #### Separator ####
    $subseq->add('separator');
    
    # New subsequence
    my $new_command = sub{
        return unless $self->current_state eq 'subseq';
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
        return unless $self->current_state eq 'subseq';
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
        return unless $self->current_state eq 'subseq';
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

## needs to be called when drawing the clone_sequences (clone sequence details not present when other menus are created)
sub populate_polyA_menu{
    my ($self ) = @_;
    
    my $menu_frame = $self->menu_bar
            or confess 'No menu Bar';
    my $menu = $self->make_menu("PolyA");
    
    my @clone_list = $self->clone_list;
    
    foreach my  $clone_name (@clone_list) {

        #warn "adding $clone_name to polyA menu";
        $menu->add( 'command' ,
                    -label => $clone_name,    
                    -command => sub { $self->launch_polyA($clone_name) },
        );
    } 
    
    $menu->bind('<Destroy>', sub{ $self = undef });
}

sub launch_polyA{
    my( $self, $clone_name ) = @_;
       
    eval {
	my $mw = undef;
	my $polyAs = $self->get_all_PolyAWindows();
	
	foreach my $hash_id(keys %$polyAs){
	    next unless $polyAs->{"$hash_id"}->slice_name eq $clone_name;
	    warn "launch_polyA found polyA with name : " . $polyAs->{"$hash_id"}->slice_name . "\n";
	    $mw = $polyAs->{"$hash_id"}->toplevel;
	    $mw->deiconify;
	    $mw->raise;
            $mw->eventGenerate('<<redraw_polya>>'); ## redraw important part from saved data, rather than use potentially unsaved data from previous use 
	}
	unless ($mw){
	    my $clone = $self->get_CloneSeq($clone_name) ;
	    $mw = $self->canvas->Toplevel;
	    my $polyA = CanvasWindow::PolyAWindow->new($mw);
	    # $polyA->add_CloneSequence( $clone ) ; # added for polya
	    $polyA->xace_seq_chooser($self);
	    $polyA->slice_name($clone_name);
	    $polyA->initialize;
	    $polyA->draw;
	    
	    $self->add_PolyAWindow($polyA);
	}
    };
    if ($@) {
	$self->exception_message("Error creating PolyA window for '$clone_name'", $@);
    }
}
sub add_PolyAWindow{
    my ($self, $polyA) = @_;
    $self->{'_PolyAWindows'}{"$polyA"} = $polyA;
}
sub get_all_PolyAWindows{
    my ($self) = @_;
    return $self->{'_PolyAWindows'};
}
sub delete_PolyAWindow {
    my( $self, $polyA ) = @_;
    $self->{'_PolyAWindows'}{"$polyA"} = undef;
    delete $self->{'_PolyAWindows'}->{"$polyA"};
}
sub withdraw_PolyAWindow {
    my( $self, $polyA ) = @_;
    $self->{'_PolyAWindows'}{"$polyA"}->toplevel->withdraw();
}

sub close_all_PolyAWindows {
    my( $self ) = @_;

    my $polyAs = $self->get_all_PolyAWindows();

    foreach my $hash_id (keys %$polyAs) {
	my $polyA = $polyAs->{"$hash_id"};
        my $top = $polyA->toplevel;
        # Send save message
        $top->deiconify;
        $top->raise;
        $top->update;
        $top->focus;

        my $opt = $polyA->close_window();
	# wanted to use this method, but eventGenerate() doesn't seem to return
	# the value of the code it executes for you.
	# my $opt = $top->eventGenerate('<Control-w>');

	# so $opt = 1 unless user hit cancel

	# clean out the cache of polyAs, unless user hit cancel at some point
	$self->delete_PolyAWindow($polyA) if $opt;

	# not sure this was right
	# if ($top) {
	#     warn "polyA edit window '$hash_id' was not closed its still a $top\n";
	#     return 0;
	# }
    }
    $polyAs = $self->get_all_PolyAWindows() || {};
    # check that all the polyAWindows have been removed
    # return 0 if there are still polyAs
    return scalar(keys %$polyAs) ? 0 : 1;
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

sub exit_save_data {
    my( $self ) = @_;

    my $ace = $self->AceDatabase;
    unless ($self->write_access) {
        $ace->error_flag(0);
	$self->close_all_PolyAWindows; # free some memory when read only
        $self->kill_xace;
        return 1;
    }
    
    $self->close_all_edit_windows or return;
    
    # Ask the user if any changes should be saved
    my $dialog = $self->canvas->toplevel->Dialog(
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
    $self->close_all_LocusWindows ;
    $self->close_all_PolyAWindows        or return;
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
    my $top = $self->canvas->toplevel;

    $top->Busy;

    my $db = $self->AceDatabase;
    eval{
        my $ace_data = $db->save_all_slices;
        ## update_ace should be true unless this object is exiting
        if($update_ace && ref($ace_data) eq 'SCALAR'){
            $self->launch_xace;
            $self->update_ace_display($$ace_data);
            # resync here!
            $self->resync_with_db; # probably better to create a key event
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

sub command_line_restart {
    my( $self ) = @_;

    if (my @exec = @main::command_line) {
        if (my $pid = fork) {
            $self->canvas->toplevel->destroy;
        }
        elsif (defined $pid) {
            exec(@exec);
        }
        else {
            $self->message("Error: Can't fork");
        }
    } else {
        $self->message("Can't see command_line in main package");
    }
}

sub edit_double_clicked {
    my( $self ) = @_;
    
    return unless $self->list_selected;
    
    my $canvas = $self->canvas;
    $canvas->Busy;
    if ($self->current_state eq 'clone') {
        $self->save_selected_clone_names;
        $self->current_state('subseq');
        $self->draw_current_state;
    } else {
        $self->edit_subsequences;
    }
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
    
    if (@clone_names) {
        $self->draw_subseq_list(@clone_names);
    } else {
        $self->message('No clone selected');
    }
}

sub _make_search {
    my ($self) = @_;

    my $top = $self->canvas->toplevel();
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
    
    #cluck "Called ace_handle";
    
    if ($adbh) {
        $self->{'_ace_database_handle'} = $adbh;
    } else {
        unless ($adbh = $self->{'_ace_database_handle'}) {
            if (my $local = $self->local_server) {
                $adbh = $self->{'_ace_database_handle'} 
                      = $local->ace_handle;
            }
            elsif (my $path = $self->ace_path) {
                $adbh = $self->{'_ace_database_handle'}
                      = Ace->connect(
                    -PATH       => $path,
                    -PROGRAM    => 'tace',
                    ) or die "Can't connect to db '$path' :\n", Ace->error;
            }
            else {
                confess "I don't know where the database is";
            }
        }
        $adbh->auto_save(0);
        $adbh->{database}->auto_save(0);
    }
    return $adbh;
}

sub ace_path {
    my( $self, $path ) = @_;
    
    if ($path) {
        $self->{'_ace_path'} = $path;
    }
    return $self->{'_ace_path'};
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
        $adbh->fetch(Assembly => '*');
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

sub current_clone_name {
    my( $self ) = @_;
    
    my $clone_name;
    my @selected_clone = $self->list_selected_clone_names;
    my      @all_clone = $self->clone_list;

    if (@selected_clone == 1) {
        $clone_name = $selected_clone[0];
    }
    elsif (@all_clone == 1) {
        $clone_name = $all_clone[0];
    }
    
    return $clone_name;
}

sub edit_new_subsequence {
    my( $self ) = @_;
    
    my @sub_names = $self->list_selected_subseq_names;
    my( $clone_name, @subseq );
    foreach my $sn (@sub_names) {
        my $sub = $self->get_SubSeq($sn);
        my $this_clone = $sub->clone_Sequence->name;
        if ($clone_name) {
            if ($clone_name ne $this_clone) {
                $self->message("ERROR: selected SubSequences are attached to different Sequences");
                return;
            }
        } else {
            $clone_name = $this_clone;
        }
        push(@subseq, $sub);
    }
    
    $clone_name ||= $self->current_clone_name;
    unless ($clone_name) {
       $self->message("Unable to determine clone name");
       return;
    }
    
    my( $most_3prime, @ints );
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
    
    my $clone = $self->get_CloneSeq($clone_name);
    my $region_name = $clone->clone_name_overlapping($most_3prime) || $clone_name;
    #warn "Looking for clone overlapping '$most_3prime' in '$clone_name' found '$region_name'";
    
    # Trim sequence version from accession if clone_name ends .SV
    $region_name =~ s/\.\d+$//;

    my $regex = qr{^(?:[^:]+:)?$region_name\.(\d+)}; # qr is a Perl 5.6 feature
    my $max = 0;
    foreach my $sub ($clone->get_all_SubSeqs) {
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
        $new->clone_Sequence($clone->Sequence);
        
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
    my $gm = $self->get_default_mutable_GeneMethod or confess "No default mutable GeneMethod";
    

    ## problem where translation was not being set on newly created 'Coding' SubSeq's
    if ($gm->is_coding){        
        $new->translation_region( $new->start , $new->end) ;
    }
    
    $new->GeneMethod($gm);

    $clone->add_SubSeq($new);

    $self->add_SubSeq($new);
    $self->do_subseq_display;
    $self->highlight_by_name('subseq', $seq_name);
    $self->make_exoncanvas_edit_window($new);
    
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
    $xr->send_command('gif ; seqrecalc');
    
    # Remove from our objects
    foreach my $sub (@to_die) {
        $self->delete_SubSeq($sub);
    }
    
    $self->draw_current_state;
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
    $var->name($var_name);
    $self->add_SubSeq($var);
    $clone->add_SubSeq($var);
    
    $self->draw_current_state;
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

sub close_all_subseq_edit_windows {
    my( $self ) = @_;

    my $mw = $self->canvas->toplevel;
    foreach my $name ($self->list_all_subseq_edit_window_names) {
        my $top = $self->get_subseq_edit_window($name) or next;
        # Tell window to close
        $top->deiconify;
        $top->raise;
        $top->update;
        $top->focus;
        $top->eventGenerate('<Control-w>');
        # User pressed "Cancel" if window is still there
        return 0 if $self->get_subseq_edit_window($name);
    }
    
    return 1;
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


sub draw_subseq_list {
    my( $self, @selected_clones ) = @_;

    
    my $canvas = $self->canvas;
    
    my( @subseq );
    my $counter = 1;
    foreach my $clone_name (@selected_clones) {
        my $clone = $self->get_CloneSeq($clone_name)
            or confess "Can't get Clone '$clone_name'";
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

sub get_stored_SubSeq_hash{
    my ($self) = @_ ;
    return $self->{'_subsequence_cache'} ;
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

sub get_Sequences_of_all_clones {
    my( $self ) = @_;
    
    my( @seq );
    foreach my $name ($self->clone_list) {
        push(@seq, $self->get_CloneSeq($name)->Sequence);
    }
    return @seq;
}

sub run_dotter {
    my( $self ) = @_;
    
    my $dw = $self->{'_dotter_window'};
    unless ($dw) {
        my $parent = $self->canvas->toplevel;
        my $top = $parent->Toplevel(-title => 'run dotter');
        $top->transient($parent);
        $dw = CanvasWindow::DotterWindow->new($top);
        $dw->initialise;
        $self->{'_dotter_window'} = $dw;
    }
    $dw->update_from_XaceSeqChooser($self);
    
    return 1;
}

sub DESTROY {
    my( $self ) = @_;
    # need to undef AceDatabase for it's clean up.
    # warn "AceDatabase->unlock should now happen\n";
    delete $self->{'_AceDatabase'}; # unlock will now happen
    # warn "AceDatabase->unlock should have happened\n";
    if (my $sn = $self->SequenceNotes){
        # then refresh locks
        # warn "lock refresh should now happen\n";
        $sn->refresh_column(7) ; ## locks column
        # warn "lock refresh should have happened\n";
        # need to clean up the sequenceNotes reference
        delete $self->{'_sequence_notes'} ;
    }
    warn "Destroying XaceSeqChooser for ", $self->ace_path, "\n";
}

1;

__END__

=head1 NAME - MenuCanvasWindow::XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

