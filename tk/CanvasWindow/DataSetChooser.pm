
### CanvasWindow::DataSetChooser

package CanvasWindow::DataSetChooser;

use strict;
use Carp;
use base 'CanvasWindow';
use CanvasWindow::SequenceSetChooser;
use File::Path 'rmtree';

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    my $canvas = $self->canvas;
    $canvas->Tk::bind('<Button-1>', sub{
            $self->deselect_all;
            $self->select_dataset;
        });
    my $edit_command = sub{ $self->open_dataset; };
    $canvas->Tk::bind('<Double-Button-1>',  $edit_command);
    $canvas->Tk::bind('<Return>',           $edit_command);
    $canvas->Tk::bind('<KP_Enter>',         $edit_command);
    $canvas->Tk::bind('<Control-o>',        $edit_command);
    $canvas->Tk::bind('<Control-O>',        $edit_command);
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    my $close_window = sub{
        $self->canvas->toplevel->destroy;
        $self = undef;  # $self gets nicely DESTROY'd with this
        };
    $canvas->Tk::bind('<Control-q>',    $close_window);
    $canvas->Tk::bind('<Control-Q>',    $close_window);
    $canvas->toplevel
        ->protocol('WM_DELETE_WINDOW',  $close_window);
        
    my $top = $canvas->toplevel;
    my $button_frame = $top->Frame->pack(-side => 'top', -fill => 'x');
    my $open = $button_frame->Button(
        -text       => 'Open',
        -command    => sub {
            unless ($self->open_dataset) {
                $self->message("No dataset selected - click on a name to select one");
            }
        },
        )->pack(-side => 'left');

    my $quit = $button_frame->Button(
        -text       => 'Quit',
        -command    => $close_window,
        )->pack(-side => 'right');
        
    return $self;
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub select_dataset {
    my( $self ) = @_;
    
    return if $self->delete_message;
    my $canvas = $self->canvas;
    if (my ($current) = $canvas->find('withtag', 'current')) {
        $self->highlight($current);
    } else {
        $self->deselect_all;
    }
}

sub open_dataset {
    my( $self ) = @_;
    
    return if $self->recover_old_sessions;
    
    my ($obj) = $self->list_selected;
    return unless $obj;
    
    my $canvas = $self->canvas;
    my $this_top = $canvas->toplevel;
    $canvas->Busy;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^DataSet=(.+)/) {
            my $name = $1;
            my $client = $self->Client;
            my $ds = $client->get_DataSet_by_name($name);

            my $pipe_name = Bio::Otter::Lace::Defaults::pipe_name();
            my $top = $canvas->Toplevel(-title => "DataSet $name [$pipe_name]");
            my $sc = CanvasWindow::SequenceSetChooser->new($top);

            $sc->name($name);
            $sc->Client($client);
            $sc->DataSet($ds);
            $sc->DataSetChooser($self);
            $sc->draw;
            $canvas->toplevel->withdraw;
            $canvas->Unbusy;
            return 1;
        }
    }
    $canvas->Unbusy;
}

sub draw {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    $canvas->toplevel->withdraw;
    my @dsl = $self->Client->get_all_DataSets;
    $canvas->toplevel->deiconify;
    $canvas->toplevel->raise;
    $canvas->toplevel->focus;

    my $font = $self->font;
    my $size = $self->font_size;
    my $row_height = int $size * 1.5;
    my $font_def = [$font, $size, 'bold'];
    for (my $i = 0; $i < @dsl; $i++) {
        my $set = $dsl[$i];
        my $x = $size;
        my $y = $row_height * (1 + $i);
        $canvas->createText(
            $x, $y,
            -text   => $set->name,
            -font   => $font_def,
            -anchor => 'nw',
            -tags   => ['DataSet=' . $set->name],
            );
    }
    $self->fix_window_min_max_sizes;
}

sub recover_old_sessions {
    my( $self ) = @_;
    
    my $existing_pid = $self->list_all_current_pid;
    
    my $tmp_dir = '/var/tmp';
    local *VAR_TMP;
    opendir VAR_TMP, $tmp_dir or die "Cannot read '$tmp_dir' : $!";
    my( @lace );
    foreach (readdir VAR_TMP) {
        if (/^lace\.(\d+)/) {
            my $pid = $1;
            next if $existing_pid->{$pid};
            my $lace_dir = "$tmp_dir/$_";
            # Skip if directory is not ours
            my $owner = (stat($lace_dir))[4];
            next unless $< == $owner;
            push(@lace, $lace_dir);
        }
    }
    closedir VAR_TMP or die "Error closing directory '$tmp_dir' : $!";
    
    for (my $i = 0; $i < @lace;) {
        my $ace_wrm = "$lace[$i]/database/ACEDB.wrm";
        if (-e $ace_wrm) {
            $i++;
        } else {
            print STDERR "\nNo such file: '$ace_wrm'\nDeleting uninitialized database '$lace[$i]'\n";
            rmtree($lace[$i]);
            splice(@lace, $i, 1);
        }
    }
    
    if (@lace) {
        my $text = "Recover these lace sessions?\n"
            . join('', map "$_\n", @lace);
        
        # Ask the user if changes should be saved
        my $dialog = $self->canvas->toplevel->Dialog(
            -title          => 'Recover sessions?',
            -bitmap         => 'question',
            -text           => $text,
            -default_button => 'Yes',
            -buttons        => [qw{ Yes No }],
            );
        my $ans = $dialog->Show;

        if ($ans eq 'No') {
            return 0;
        }
        elsif ($ans eq 'Yes') {
            eval{
                $self->make_XaceSeqChooser_windows(@lace);
            };
            if ($@) {
                $self->exception_message($@, 'Error recovering lace sessions');
            }
            return 1;
        }
    } else {
        return 0;
    }
}

sub list_all_current_pid {
    my( $self ) = @_;
    
    my $current = {};
    
    local *PID;

    my $pipe = $^O =~ /solaris/i ? "ps -A |" : "ps ax |";
    open PID, $pipe or die "Cannot open pipe '$pipe' : $!";
    while (<PID>) {
        my ($pid) = split;
        next unless $pid =~ /^\d+$/;
        $current->{$pid} = 1;
    }
    close PID or die "Error running '$pipe' : exit $?";
    
    return $current;
}

sub make_XaceSeqChooser_windows {
    my( $self, @dirs ) = @_;
    
    my $canvas = $self->canvas;
    my $cl     = $self->Client;
    
    my $i = 1;
    
    my $cl_write_setting = $cl->write_access();
    my $readonly_tag     = $cl->ace_readonly_tag();
    $readonly_tag        =~ s{(\W)}{\\$1}g;

    foreach my $dir (@dirs) {

        my $write = ($dir =~ /$readonly_tag/ ? 0 : 1);
        # Has to be set before call to $cl->new_AceDatabase
        # as that calls $db->home which sets the home using whatever
        # $cl_write_setting is NOT the write status of the
        # db being recovered!
	    $cl->write_access($write);

        ### Can recover title from wspec/displays.wrm
        #my $title = "Recover $i";
        my $db = $cl->new_AceDatabase;
        $db->error_flag(1);

	
        my $home = $db->home;
        rename($dir, $home) or die "Cannot move '$dir' to '$home' : $!";
        
        # warn "home directory $home";
        
        my $title = "Recover ". $self->add_title($db);
        
        $db->title($title);
        
        $db->recover_slice_dataset_hash;

        # Bring up GUI
        my $top = $canvas->Toplevel(
            -title  => $title,
            );
        my $xc = MenuCanvasWindow::XaceSeqChooser->new($top);
        $xc->AceDatabase($db);
        $xc->write_access($write);
        $xc->initialize;

        $i++;
    }
    # restore client's original setting
    $cl->write_access($cl_write_setting);
}

sub add_title{
    my ($self , $db ) = @_ ;
    
    my $file =   $db->home . '/wspec/displays.wrm';
    warn "opening file $file";
    open ( DISPLAY , $file) || die "$!"   ;
        
    foreach my $line (<DISPLAY>){
        #my ($name ) = ($line  =~ /_DDtMain -g TEXT_FIT -t "(.*)"/ ) ; 
        my ($name ) = ($line  =~ /_DDtMain.*-t\s*"(.*)"/ ) ;
        if ($name){
            #warn   "\n\n'$name'\n\n";
            return $name;
        }    
    }
    warn "\n\nno name found in $file\n\n";
}



1;

__END__

=head1 NAME - CanvasWindow::DataSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

