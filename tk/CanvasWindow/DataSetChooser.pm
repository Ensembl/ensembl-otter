
### CanvasWindow::DataSetChooser

package CanvasWindow::DataSetChooser;

use strict;
use Carp;
use base 'CanvasWindow';
use CanvasWindow::SequenceSetChooser;

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
    if (my $current = $canvas->find('withtag', 'current')) {
        $self->highlight($current);
    } else {
        $self->deselect_all;
    }
}

sub open_dataset {
    my( $self ) = @_;
    
    my ($obj) = $self->list_selected;
    return unless $obj;
    
    my $canvas = $self->canvas;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^DataSet=(.+)/) {
            my $name = $1;
            my $client = $self->Client;
            my $ds = $client->get_DataSet_by_name($name);

            my $top = $canvas->Toplevel(-title => "DataSet $name");
            my $sc = CanvasWindow::SequenceSetChooser->new($top);

            $sc->name($name);
            $sc->Client($client);
            $sc->DataSet($ds);
            $sc->DataSetChooser($self);
            $sc->draw;
            $canvas->toplevel->withdraw;
            return 1;
        }
    }
}

sub draw {
    my( $self ) = @_;
    
    my @dsl = $self->Client->get_all_DataSets;
    my $font = $self->font;
    my $size = $self->font_size;
    my $canvas = $self->canvas;
    my $font_def = [$font, $size, 'bold'];
    for (my $i = 0; $i < @dsl; $i++) {
        my $set = $dsl[$i];
        my $x = $size;
        my $y = $size * (1 + $i);
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

1;

__END__

=head1 NAME - CanvasWindow::DataSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

