
### CanvasWindow::SequenceSetChooser

package CanvasWindow::SequenceSetChooser;

use strict;
use Carp;
use base 'CanvasWindow';
use CanvasWindow::SequenceNotes;

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    my $canvas = $self->canvas;
    $canvas->Tk::bind('<Button-1>', sub{
            $self->deselect_all;
            $self->select_sequence_set;
        });
    my $edit_command = sub{ $self->open_sequence_set; };
    $canvas->Tk::bind('<Double-Button-1>',  $edit_command);
    $canvas->Tk::bind('<Return>',           $edit_command);
    $canvas->Tk::bind('<KP_Enter>',         $edit_command);
    $canvas->Tk::bind('<Control-o>',        $edit_command);
    $canvas->Tk::bind('<Control-O>',        $edit_command);
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    my $close_window = sub{
        my $top = $self->DataSetChooser->canvas->toplevel;
        $top->deiconify;
        $top->raise;
        $self->canvas->toplevel->destroy;
        $self = undef;  # $self will not get DESTROY'd without this
        };
    $canvas->Tk::bind('<Control-w>',                $close_window);
    $canvas->Tk::bind('<Control-W>',                $close_window);
    $canvas->toplevel->protocol('WM_DELETE_WINDOW', $close_window);

        
    my $top = $canvas->toplevel;
    my $button_frame = $top->Frame->pack(-side => 'top', -fill => 'x');
    my $open = $button_frame->Button(
        -text       => 'Open',
        -command    => sub {
            unless ($self->open_sequence_set) {
                $self->message("No SequenceSet selected - click on one to select");
            }
        },
        )->pack(-side => 'left');
    
    my $quit = $button_frame->Button(
        -text       => 'Close',
        -command    => $close_window,
        )->pack(-side => 'right');
    
    return $self;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub DataSet {
    my( $self, $DataSet ) = @_;
    
    if ($DataSet) {
        $self->{'_DataSet'} = $DataSet;
    }
    return $self->{'_DataSet'};
}

sub DataSetChooser {
    my( $self, $DataSetChooser ) = @_;
    
    if ($DataSetChooser) {
        $self->{'_DataSetChooser'} = $DataSetChooser;
    }
    return $self->{'_DataSetChooser'};
}

sub draw {
    my( $self ) = @_;
    
    my $font    = $self->font;
    my $size    = $self->font_size;
    my $canvas  = $self->canvas;

    my $font_def = [$font,       $size, 'bold'];
    my $helv_def = ['Helvetica', $size, 'normal'];

    my $ds = $self->Client->get_DataSet_by_name($self->name);
    my $ss_list = $ds->get_all_SequenceSets;
    my $row_height = int $size * 1.5;
    my $x = $size;
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $set = $ss_list->[$i];
        my $row = $i + 1;
        my $y = $row_height * $row;
        $canvas->createText(
            $x, $y,
            -text   => $set->name,
            -font   => $font_def,
            -anchor => 'nw',
            -tags   => ["row=$row", 'SetName', 'SequenceSet=' . $set->name],
            );
    }
    
    $x = ($canvas->bbox('SetName'))[2] + ($size * 2);
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $set = $ss_list->[$i];
        my $row = $i + 1;
        my $y = $row_height * $row;
        $canvas->createText(
            $x, $y,
            -text   => $set->description,
            -font   => $helv_def,
            -anchor => 'nw',
            -tags   => ["row=$row", 'SetDescription', 'SequenceSet=' . $set->name],
            );
    }
    
    $x = $size;
    my $max_x = ($canvas->bbox('SetDescription'))[2];
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $set = $ss_list->[$i];
        my $row = $i + 1;
        my $y = $row_height * $row;
        my $rec = $canvas->createRectangle(
            $x, $y, $max_x, $y + $size,
            -fill       => undef,
            -outline    => undef,
            -tags   => ["row=$row", 'SetBackground', 'SequenceSet=' . $set->name],
            );
        $canvas->lower($rec, "row=$row");
    }
    
    
    $self->fix_window_min_max_sizes;
}

sub select_sequence_set {
    my( $self ) = @_;
    
    return if $self->delete_message;
    my $canvas = $self->canvas;
    if (my $current = $canvas->find('withtag', 'current')) {
        my( $ss_tag );
        foreach my $tag ($canvas->gettags($current)) {
            if ($tag =~ /^SequenceSet=/) {
                $ss_tag = $tag;
                last;
            }
        }
        if ($ss_tag) {
            $self->highlight($ss_tag);
        }
    } else {
        $self->deselect_all;
    }
}

sub open_sequence_set {
    my( $self ) = @_;
    
    my ($obj) = $self->list_selected;
    my $canvas = $self->canvas;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^SequenceSet=(.+)/) {
            my $name = $1;
            if (my $win = $self->{'_sequence_notes_window'}{$name}) {
                $win->deiconify;
                $win->raise;
                return 1;
            }
            
            my $this_top = $canvas->toplevel;
            
            ### in this case Busy() seems to globally grab pointer - why?
            ### grabStatus reports 'local' - but it is a global grab.
            #$this_top->Busy(
            #    -recurse    => 1,
            #    );   
            #my $status = $this_top->grabStatus;
            #warn "grab = $status\n";
            
            ## Using this instead:
            $this_top->configure(-cursor => 'watch');
            
            my $top = $self->{'_sequence_notes_window'}{$name} =
                $this_top->Toplevel(-title => "SequenceSet $name");
            my $ss = $self->DataSet->get_SequenceSet_by_name($name);

            my $sn = CanvasWindow::SequenceNotes->new($top);
            $sn->name($name);
            $sn->Client($self->Client);
            $sn->SequenceSet($ss);
            $sn->SequenceSetChooser($self);
            $sn->initialise;
            $sn->draw;
            
            
            #$this_top->Unbusy;
            $this_top->configure(-cursor => undef);
            
            return 1;
        }
    }
    return;
}

sub DESTROY {
    my( $self ) = @_;

    my ($type) = ref($self) =~ /([^:]+)$/;
    my $name = $self->name;
    warn "Destroying $type $name\n";
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

