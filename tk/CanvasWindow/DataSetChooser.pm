
### CanvasWindow::DataSetChooser

package CanvasWindow::DataSetChooser;

use strict;
use Carp;
use base 'CanvasWindow';


sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    my $canvas = $self->canvas;
    $canvas->Tk::bind('<Button-1>', sub{
            $self->select_dataset;
        });
    my $edit_command = sub{ $self->open_dataset; };
    $canvas->Tk::bind('<Double-Button-1>',  $edit_command);
    $canvas->Tk::bind('<Return>',           $edit_command);
    $canvas->Tk::bind('<KP_Enter>',         $edit_command);
    $canvas->Tk::bind('<Control-o>',        $edit_command);
    $canvas->Tk::bind('<Control-O>',        $edit_command);
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
        
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
    
    foreach my $tag ($self->canvas->gettags($obj)) {
        if ($tag =~ /DataSet=(.+)/) {
            my $name = $1;
            $self->message("Going to open '$name'");
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
            -tags   => ['DataSet=' . $set->name],
            );
    }
}

1;

__END__

=head1 NAME - CanvasWindow::DataSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

