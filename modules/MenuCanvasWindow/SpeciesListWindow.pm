
### MenuCanvasWindow::SpeciesListWindow

package MenuCanvasWindow::SpeciesListWindow;

use strict;
use warnings;

use Carp;
use Bio::Otter::Log::Log4perl 'logger';
use Try::Tiny;
use Tk::DialogBox;

use Zircon::ZMap;

use Bio::Otter::Utils::About;
use Bio::Otter::UI::AboutBoxMixIn;
use Bio::Otter::Lace::Client;
use Bio::Vega::Utils::URI qw( open_uri );
use Tk::ScopedBusy;

use MenuCanvasWindow::ColumnChooser;
use EditWindow::Preferences;
use CanvasWindow::SequenceSetChooser;

use base qw( MenuCanvasWindow );

sub new {
    my ($pkg, @args) = @_;

    @args = (@args, 220, 150, 'ose') if 1 == @args;
    # Default params:
    #
    # x width: wide enough to show full title text (worksforme size),
    # and for comfortable yellow-sticky-messages
    #
    # ose: size fitting doesn't account for 'o' scrollbar.  Leave east
    # on, we won't need the south.

    my $self = $pkg->SUPER::new(@args);
    my $top = $self->top_window;

    my $canvas = $self->canvas;
    $canvas->Tk::bind('<Button-1>', sub{
            $self->deselect_all;
            $self->select_dataset;
        });
    my $open_command = sub{
        unless ($self->open_dataset) {
            $self->message("No dataset selected - click on a name to select one");
        }
    };
    $canvas->Tk::bind('<Double-Button-1>',  $open_command);
    $canvas->Tk::bind('<Return>',           $open_command);
    $canvas->Tk::bind('<KP_Enter>',         $open_command);
    $canvas->Tk::bind('<Control-o>',        $open_command);
    $canvas->Tk::bind('<Control-O>',        $open_command);
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });

    my $shortcut_command = sub { $self->show_shortcut_window; };
    $top->Tk::bind('<Control-s>', $shortcut_command);
    $top->Tk::bind('<Control-S>', $shortcut_command);

    my $recover_command = sub{ $self->recover_some_sessions('explicit'); };
    $top->Tk::bind('<Control-r>',    $recover_command);
    $top->Tk::bind('<Control-R>',    $recover_command);

    my $prefs_command = [ $self, 'show_preferences' ];
    $top->Tk::bind('<Control-p>', $prefs_command);
    $top->Tk::bind('<Control-P>', $prefs_command);

    my $quit_command = $self->bind_WM_DELETE_WINDOW('quit_command');
    $top->Tk::bind('<Control-q>',    $quit_command);
    $top->Tk::bind('<Control-Q>',    $quit_command);


    # FILE MENU
    my $file_menu = $self->make_menu('File');

    $file_menu->add
       ('command',
        -label      => 'Open',
        -accelerator => 'Ctrl+O',
        -underline  => 1,
        -command    => $open_command);

    $file_menu->add
        ('command',
         -label       => 'Open by shortcut',
         -accelerator => 'Ctrl+S',
         -underline   => 1,
         -command     => $shortcut_command);

    $file_menu->add
       ('command',
        -label      => "Recover sessions",
        -accelerator => 'Ctrl+R',
        -underline  => 1,
        -command    => $recover_command,
       );

    $file_menu->add
       ('command',
        -label      => "Preferences...",
        -accelerator => 'Ctrl+P',
        -underline  => 1,
        -command    => $prefs_command,
       );

    $file_menu->add
       ('command',
        -label      => 'Quit',
        -accelerator => 'Ctrl+Q',
        -underline  => 1,
        -command    => $quit_command,
       );


    # HELP MENU
    my $help_menu = $self->make_menu('Help', 0, 'right');
    $help_menu->add
      ('command',
       -label => 'About Otter...',
       -underline => 0,
       -command => [ $self, 'show_about' ]);

    $help_menu->add
      ('command',
       -label => 'Show Error Log',
       -underline => 11,
       -command => [ $self, 'show_log' ]);

    return $self;
}

sub quit_command {
    my ($self) = @_;
    $self->zircon_delete; # we *must* do this explicitly before the next line
    $self->canvas->toplevel->destroy;
    return;
}


sub ensure_tools {
    my ($self) = @_;

    # Check `zmap --version` et al., lest we load up a session before
    # finding its absence.
    my @v = try {
        Bio::Otter::Utils::About->tools_versions;
    } catch {
        $self->logger->error("_ensure_tools: $_");
        ();
    };

    # Check we are running a sensible Otter version
    $self->uptodate_check;

    if (@v) {
        local $" = "\n  ";
        $self->logger->info("Tools are\n  @v");
    } else {
        $self->message("Some parts of Otter are not working\n".
                       "See Help > About... for info");
    }

    return ();
}

sub uptodate_check {
    my ($self) = @_;

    my ($do_warn, $colour, $description) = try {
        Bio::Otter::Utils::About->version_diagnosis;
    } catch {
        $self->logger->error("_ensure_tools: $_");
        (1, 'grey', 'broken in some way');
    };

    $self->canvas->configure(-background => $colour);
    if ($do_warn) {
        $self->message("This is $description");
    } else {
        $self->logger->info("This is $description");
    }
    return;
}

sub show_about {
    my ($self) = @_;

    $self->{'_about'} ||= do {
        my $content = Bio::Otter::Utils::About->about_text;
        $self->Bio::Otter::UI::AboutBoxMixIn::make_box('About Otter', $content);
    };

    $self->{'_about'}->Show;

    return ();
}

sub show_preferences {
    my ($self, %opt) = @_;

    EditWindow::Preferences->init_or_reuse_Toplevel
        (-title => 'Preferences',
         { reuse_ref => \$self->{_prefs_win},
           from => $self->top_window,
           init => { Client => $self->Client },
           raise => 1,
           %opt });
    return ();
}

# Find the link near click & open it
sub about_hyperlink {
    my ($self, $txt, $at) = @_;
    my @idx = $txt->tagPrevrange(link => $at);
    my $ln = $txt->get(@idx);
    open_uri($ln);
    return ();
}


sub show_log{
    my ($self) = @_;

    require TransientWindow::LogWindow;
    my $tw = TransientWindow::LogWindow->show_for($self->top_window);

    return;
}

{
    my $shortcut;

    sub show_shortcut_window {
        my ($self) = @_;

        my $shortcut_window = $self->{'_shortcut_window'};
        unless ($shortcut_window) {

            $shortcut_window = $self->top_window->DialogBox(
                -title          => 'Open by shortcut',
                -buttons        => [ qw( Open Clear Cancel ) ],
                -default_button => 'Open',
                -cancel_button  => 'Cancel',
                );

            my $text = << "__EO_TEXT__";
Format:\t<dataset>[/<seqset>[/<region>]]
Examples:
        mouse                                   # Dataset
        mouse/chr12-38                          # SequenceSet
        mouse/chr12-38/3_000_000:4_000_000      # Region, by coords
        mouse/chr12-38/3_000_000+1_000_000      # Region, by start + length
        mouse/chr12-38/#5..8                    # Region, by clone indices
        mouse/chr12-38/CR974568.14-CT572999.10  # Region, by start-end names
        mouse/chr12-38/view:...                 # Region, read-only
__EO_TEXT__
            my @lines = ( $text =~ /(\n)/g );
            chomp $text;
            $text =~ s/^\s+/\t/mg; # leading space to single tab
            $text =~ s/\s+#/\t#/g; # pre-comment space to single tab

            my $text_widget = $shortcut_window->add(
                'ROText',
                -selectborderwidth => 0,
                -borderwidth => 0,
                -font => $self->named_font('prop'),
                -height => scalar @lines,
                -tabs => [ qw( 2.5c 12c ) ],
                )->pack(-side => 'top', -fill => 'both', -expand => 1);
            $text_widget->Insert($text);

            my $shortcut_le_widget = $shortcut_window->add(
                'LabEntry',
                -label        => 'Shortcut',
                -labelPack    => [-side => 'left'],
                -textvariable => \$shortcut,
                -width        => 80,
                )->pack;
            $shortcut_window->configure( -focus => $shortcut_le_widget );

            $self->{'_shortcut_window'} = $shortcut_window;
        }

        my $answer;
        while (($answer = $shortcut_window->Show) eq 'Clear') {
            $shortcut = '';
        }
        if ($answer eq 'Open') {
            require Bio::Otter::Utils::AutoOpen; # load iff needed
            my $opener = Bio::Otter::Utils::AutoOpen->new($self);
            $opener->parse_path($shortcut);
        }

        return;
    }
}


sub Client {
    my ($self, $Client) = @_;

    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub select_dataset {
    my ($self) = @_;

    return if $self->delete_message;
    my $canvas = $self->canvas;
    if (my ($current) = $canvas->find('withtag', 'current')) {
        $self->highlight($current);
    } else {
        $self->deselect_all;
    }

    return;
}

sub open_dataset {
    my ($self) = @_;

    return 1 if $self->recover_some_sessions('implicit');

    my ($obj) = $self->list_selected;
    return 0 unless $obj;

    my $canvas = $self->canvas;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^DataSet=(.+)/) {
            my $name = $1;
            $self->open_dataset_by_name($name);
            return 1;
        }
    }

    return 0;
}

# Returns the CW:SequenceSetChooser
sub open_dataset_by_name {
    my ($self, $name) = @_;

    my $client = $self->Client;
    my $ds = $client->get_DataSet_by_name($name);

    my $canvas = $self->canvas;
    my $busy = Tk::ScopedBusy->new($canvas);

    my $ssc = CanvasWindow::SequenceSetChooser->init_or_reuse_Toplevel(
        -title => "Assembly List $name",
        {
            from      => $canvas,
            reuse_ref => \$self->{'_sequence_set_chooser'}{$name},
            raise     => 1,
            init      => {
                name              => $name,
                Client            => $client,
                DataSet           => $ds,
                SpeciesListWindow => $self
            },
        }
    );

    return $ssc;
}

sub cached_SequenceSetChoser_by_name {
    my ($self, $name) = @_;

    return $self->{'_sequence_set_chooser'}{$name};
}

sub draw {
    my ($self) = @_;

    my $canvas = $self->canvas;

    $canvas->toplevel->withdraw;
    my @dsl = $self->Client->get_all_DataSets;
    $canvas->toplevel->deiconify;
    $canvas->toplevel->raise;
    $canvas->toplevel->focus;

    my ($font, $size, $row_height) =
      $self->named_font(listbold => 'linespace', 'linegap');
    $row_height = int 1.2 * $row_height;
    for (my $i = 0; $i < @dsl; $i++) {
        my $data_set = $dsl[$i];
        my $x = $size;
        my $y = $row_height * (1 + $i);
        my $ro = $data_set->READONLY ? ' (r-o)' : '';
        $canvas->createText(
            $x, $y,
            -text   => $data_set->name . $ro,
            -font   => $font,
            -fill   => $ro ? 'DarkRed' : 'DarkGreen', # matches CW:SequenceSetChooser->draw
            -anchor => 'nw',
            -tags   => ['DataSet=' . $data_set->name],
            );
    }
    $self->fix_window_min_max_sizes;

    return;
}

sub recover_some_sessions {
    my ($self, $cause) = @_;

    my $client = $self->Client();
    my $recoverable_sessions = $client->sessions_needing_recovery();
    my $n = @$recoverable_sessions;
    $self->logger->info("recover_some_sessions($cause), $n available");

    if (@$recoverable_sessions) {
        my %session_wanted = map { $_->[0] => 1 } @$recoverable_sessions;

        my $rss_dialog = $self->canvas->toplevel->DialogBox(
            -title => $Bio::Otter::Lace::Client::PFX.'Recover Sessions',
            -buttons => ['Recover', 'Cancel'],
        );
        $rss_dialog->Tk::bind('<Escape>', sub { $rss_dialog->Subwidget('B_Cancel')->invoke });

        $rss_dialog->add('Label',
            -wrap    => 400,
            -justify => 'left',
            -text    => join("\n\n",
                "You have one or more otter sessions on this computer which are not"
                . " associated with a running otter process.",

                "This should not happen, except where otter has crashed or it has"
                . " been exited by pressing the exit button in the 'Choose Dataset'"
                . " window.",

                "You will need to recover and exit these sessions. There may be"
                . " locks left in the otter database or some of your work which has"
                . " not been saved.",

                "Please contact anacode if you still get an error when you attempt"
                . " to exit the session, or have information about the error which"
                . " caused a session to be left.",
                ),
        )->pack(-side=>'top', -fill=>'x', -expand=>1);

        foreach my $rec (@$recoverable_sessions) {
            my ($session_dir, $date, $title) = @$rec;
            my $full_session_title = sprintf "%s - %s", scalar localtime($date), $title;
            my $cb = $rss_dialog->add('Checkbutton',
                -text     => $full_session_title,
                -variable => \$session_wanted{$session_dir},
                -onvalue  => 1,
                -offvalue => 0,
                -anchor   => 'w',
            )->pack(-side=>'top', -fill=>'x', -expand=>1);
        }

        # Shortcut the dialog if we're running due to @ARGV
        my $answer = ($cause eq 'no_wait') ? 'recover' : $rss_dialog->Show();

        my @selected_recs = grep { $session_wanted{$_->[0]} } @$recoverable_sessions;

        if ($answer=~/recover/i && @selected_recs) {
            try {
                foreach my $rec (@selected_recs) {
                    my ($session_dir, $date, $title) = @$rec;

                    # We carry an extra event loop on the stack until
                    # recovery is complete, to queue actions after it.
                    local $Zircon::Tk::Context::TANGLE_ACK{'MCW:SLW:recover_some_sessions'} = 1;

                    # Bring up GUI
                    my $adb = $client->recover_session($session_dir);

                    my $cc = $self->make_ColumnChoser($adb);

                    $cc->load_filters(is_recover => 1);
                }
            }
            catch {
                $self->exception_message(
                    $_, 'Error recovering otter sessions');
            };
            # XXX: we should make a stronger protest if it fails - maybe a
            # pop up error dialog, or put a sticker on the session itself
            # (if it exists).  Also, some errors have already been eaten
            # (e.g. in RT#231368)
            return 1;
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}

# Zircon interface

sub zircon_delete {
    my ($self) = @_;
    for my $zmap (@{Zircon::ZMap->list}) {
        for my $view (@{$zmap->view_list}) {
            $view->handler->delete_zmap_view;
        }
    }
    return;
}

sub make_ColumnChoser {
    my ($self, $adb) = @_;

    warn "Making ColumnChooser";

    return MenuCanvasWindow::ColumnChooser->init_or_reuse_Toplevel(
        -title => 'Select Column Data to Load',
        {
            init => {
                AceDatabase       => $adb,
                SpeciesListWindow => $self
            },
            from => $self->canvas
        },
    );
}

sub open_Slice_read_only {
    my ($self, $slice) = @_;

    return $self->_open_Slice_write_flag($slice, 0);
}

sub open_Slice {
    my ($self, $slice) = @_;

    return $self->_open_Slice_write_flag($slice, 1);
}

sub _open_Slice_write_flag {
    my ($self, $slice, $write_flag) = @_;

    my $adb = $self->Client->new_AceDatabase_from_Slice($slice);
    $adb->write_access($write_flag && $self->Client->write_access);

    if ($adb->write_access) {
        # only lock the region if we have write access.
        try { $adb->try_to_lock_the_block }
        catch {
            $adb->error_flag(0);
            $adb->write_access(0);  # Stops AceDatabase DESTROY from trying to unlock clones
            if (/Locking slice failed during locking.*do_lock failed <lost the race/s) {
                # a message concatenated in the lock_region action, from the SliceLockBroker
                $self->message("The region you are trying to open is locked\n");
            } else {
                $self->exception_message($_, 'Error initialising database');
            }
            return 0;
        }
        finally {
            try { $self->refresh_lock_columns };
        }
          or return;
    }

    my $cc = $self->make_ColumnChoser($adb);
    $cc->init_flag(1);
    return $cc;
}

sub refresh_lock_display_for_dataset_sequence_set {
    my ($self, $dataset_name, $sequenceset_name) = @_;

    printf STDERR "Updating lock display for %s > %s\n", $dataset_name, $sequenceset_name;
    my $locks_refreshed = 0;
    if (my $ssc = $self->cached_SequenceSetChoser_by_name($dataset_name)) {
        if (my $sn = $ssc->find_cached_SequenceNotes_by_name($sequenceset_name)) {
            $sn->refresh_lock_columns;
        }
    }
}

1;

__END__

=head1 NAME - MenuCanvasWindow::SpeciesListWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

