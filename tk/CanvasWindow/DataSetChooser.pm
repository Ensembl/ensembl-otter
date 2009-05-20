
### CanvasWindow::DataSetChooser

package CanvasWindow::DataSetChooser;

use strict;
use Carp;
use Tk::DialogBox;
use base 'CanvasWindow';
use EditWindow::LoadColumns;
use CanvasWindow::SequenceSetChooser;
use Bio::Otter::Lace::LocalDatabaseFactory;

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    my $canvas = $self->canvas;
    $canvas->Tk::bind('<Button-1>', sub{
            $self->deselect_all;
            $self->select_dataset;
        });
    my $open_command = sub{ $self->open_dataset; };
    $canvas->Tk::bind('<Double-Button-1>',  $open_command);
    $canvas->Tk::bind('<Return>',           $open_command);
    $canvas->Tk::bind('<KP_Enter>',         $open_command);
    $canvas->Tk::bind('<Control-o>',        $open_command);
    $canvas->Tk::bind('<Control-O>',        $open_command);
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    my $quit_command = sub{
        $self->canvas->toplevel->destroy;
        $self = undef;  # $self gets nicely DESTROY'd with this
    };
    $canvas->Tk::bind('<Control-q>',    $quit_command);
    $canvas->Tk::bind('<Control-Q>',    $quit_command);
    $canvas->toplevel
        ->protocol('WM_DELETE_WINDOW',  $quit_command);
        
    my $top = $canvas->toplevel;
    my $button_frame = $top->Frame->pack(-side => 'top', -fill => 'x');

    my $open = $button_frame->Button(
        -text       => 'Open',
        -command    => sub{
            unless ($self->open_dataset) {
                $self->message("No dataset selected - click on a name to select one");
            }
        },
    )->pack(-side => 'left');

    my $recover = $button_frame->Button(
        -text       => "Recover sessions",
        -command    => sub{
            $self->recover_some_sessions(1);
        },
    )->pack(-side => 'left');

    my $quit = $button_frame->Button(
        -text       => 'Quit',
        -command    => $quit_command,
    )->pack(-side => 'right');
        
    return $self;
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
        $self->LocalDatabaseFactory->Client($Client);
    }
    return $self->{'_Client'};
}

sub LocalDatabaseFactory {
    my $self = shift @_;

    $self->{_ldf} ||= Bio::Otter::Lace::LocalDatabaseFactory->new();

    return $self->{_ldf};
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
    
    return if $self->recover_some_sessions(1);
    
    my ($obj) = $self->list_selected;
    return unless $obj;
    
    my $canvas = $self->canvas;
    $canvas->Busy;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^DataSet=(.+)/) {
            my $name = $1;
            my $client = $self->Client;
            my $ds = $client->get_DataSet_by_name($name);

            my $top = $self->{'_sequence_set_chooser'}{$name};
            if (Tk::Exists($top)) {
                $top->deiconify;
                $top->raise;
            } else {
                $top = $canvas->Toplevel(-title => "DataSet $name");
                my $ssc = CanvasWindow::SequenceSetChooser->new($top);

                $ssc->name($name);
                $ssc->Client($client);
                $ssc->DataSet($ds);
                $ssc->DataSetChooser($self);
                $ssc->draw;

                $self->{'_sequence_set_chooser'}{$name} = $top;
            }
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

    my $font = $self->font_fixed_bold;
    my $size = $self->font_size;
    my $row_height = int $size * 1.5;
    for (my $i = 0; $i < @dsl; $i++) {
        my $set = $dsl[$i];
        my $x = $size;
        my $y = $row_height * (1 + $i);
        $canvas->createText(
            $x, $y,
            -text   => $set->name,
            -font   => $font,
            -anchor => 'nw',
            -tags   => ['DataSet=' . $set->name],
            );
    }
    $self->fix_window_min_max_sizes;
}

sub last_selection {
    my( $self, $species, $last ) = @_;
    $self->{'_last_selection'}->{$species} = $last if $last;
    return $self->{'_last_selection'}->{$species};
}

sub default_selection {
    my( $self, $species, $default ) = @_;
    $self->{'_default_selection'}->{$species} = $default if $default;
    return $self->{'_default_selection'}->{$species};
}

sub last_sorted_by {
    my( $self, $species, $last ) = @_;
    $self->{'_last_sorted_by'}->{$species} = $last if $last;
    return $self->{'_last_sorted_by'}->{$species};
}

sub recover_some_sessions {
    my $self          = shift @_;
    my $default_state = shift @_ || 0;

    my $ldf = $self->LocalDatabaseFactory();
    my $recoverable_sessions = $ldf->sessions_needing_recovery();
    
    if (@$recoverable_sessions) {
        my %session_wanted = map { ($_ => $default_state) } @$recoverable_sessions;

        my $rss_dialog = $self->canvas->toplevel->DialogBox(
            -title => 'Recover sessions',
            -buttons => ['Recover selected sessions', 'Not at this time, thanks']
        );

        $rss_dialog->add('Label',
            -wrap    => 400,
            -justify => 'left',
            -text    => "You have one or more lace sessions on this computer which are not associated with a running otterlace process.\n\n This should not happen, except where lace has crashed or it has been exited by pressing the exit button in the dataset chooser window.\n\n You will need to recover and exit these sessions, or there may be locks left in the otter database or some of your work which has not been saved.\n\n Please contact anacode if you still get an error when you attempt to exit the session, or have information about the error which caused a session to be left.\n\n" 
        )->pack(-side=>'top', -fill=>'x', -expand=>1);
        
        # this sort is inefficient, but the list shouldn't be too long...
        $recoverable_sessions = [
            sort {
                $ldf->make_title($a) cmp $ldf->make_title($b)
            } @$recoverable_sessions
        ];
        
        foreach my $session_dir (@$recoverable_sessions) {
            my $full_session_title = $ldf->make_title($session_dir).' in '.$session_dir;
            my $cb = $rss_dialog->add('Checkbutton',
                -text     => $full_session_title,
                -variable => \$session_wanted{$session_dir},
                -onvalue  => 1,
                -offvalue => 0,
                -anchor   => 'w',
            )->pack(-side=>'top', -fill=>'x', -expand=>1);
        }

        my $answer = $rss_dialog->Show();

        my @selected_dirs = grep { $session_wanted{$_} } @$recoverable_sessions;

        if($answer=~/recover/i && @selected_dirs) {
            eval{
                my $canvas = $self->canvas;

                foreach my $session_dir (@selected_dirs) {
                    # Bring up GUI
                    my $adb = $ldf->recover_session($session_dir);
                    
                    my $top = $canvas->Toplevel(
                        -title  => 'Select column data to load',
                    );
                    
                    my $lc = EditWindow::LoadColumns->new($top);
                    
                    $lc->AceDatabase($adb);
                    $lc->DataSetChooser($self);
                    $lc->initialize;
                    $lc->change_checkbutton_state('deselect');
                    $lc->load_filters;
                    $lc->top->withdraw;
                }
            };
            if ($@) {
                $self->exception_message($@, 'Error recovering lace sessions');
            }
            return 1;
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}


1;

__END__

=head1 NAME - CanvasWindow::DataSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

