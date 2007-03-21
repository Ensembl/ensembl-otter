
### CanvasWindow::DataSetChooser

package CanvasWindow::DataSetChooser;

use strict;
use Carp;
use base 'CanvasWindow';
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

sub LocalDatabaseFactory {
    my $self = shift @_;

    $self->{_ldf} ||= Bio::Otter::Lace::LocalDatabaseFactory->new($self->Client());

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
    
    return if $self->recover_old_sessions_dialogue;
    
    my ($obj) = $self->list_selected;
    return unless $obj;
    
    my $canvas = $self->canvas;
    $canvas->Busy;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^DataSet=(.+)/) {
            my $name = $1;
            my $client = $self->Client;
            my $ds = $client->get_DataSet_by_name($name);

            my $pipe_name = Bio::Otter::Lace::Defaults::pipe_name();
            my $top = $canvas->Toplevel(-title => "DataSet $name [$pipe_name]");
            my $ssc = CanvasWindow::SequenceSetChooser->new($top);

            $ssc->name($name);
            $ssc->Client($client);
            $ssc->DataSet($ds);
            $ssc->DataSetChooser($self);
            $ssc->draw;
            # $canvas->toplevel->withdraw;
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

sub recover_old_sessions_dialogue {
    my( $self ) = @_;
    
    my $lace_sessions = $self->LocalDatabaseFactory->sessions_needing_recovery();
    
    if (@$lace_sessions) {
        my $text = "Recover these lace sessions?\n"
            . join('', map "$_\n", @$lace_sessions);
        
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
                my $canvas = $self->canvas;

                foreach my $dir (@$lace_sessions) {
                    my $adb = $self->LocalDatabaseFactory->recover_session($dir);

                    # Bring up GUI
                    my $top = $canvas->Toplevel(
                        -title  => $adb->title(),
                    );
                    my $xc = MenuCanvasWindow::XaceSeqChooser->new($top);
                    $xc->AceDatabase($adb);
                    $xc->initialize;
                }
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


1;

__END__

=head1 NAME - CanvasWindow::DataSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

