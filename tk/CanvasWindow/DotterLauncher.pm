
### CanvasWindow::DotterLauncher

package CanvasWindow::DotterLauncher;

use strict;
use Carp;
use base 'CanvasWindow';
use Data::Dumper;

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    my $canvas = $self->canvas;
#     $canvas->Tk::bind('<Button-1>', sub{
#             $self->deselect_all;
#             $self->select_sequence_set;
#         });
#     my $edit_command = sub{ $self->open_sequence_set; };
#     $canvas->Tk::bind('<Double-Button-1>',  $edit_command);
#     $canvas->Tk::bind('<Return>',           $edit_command);
#     $canvas->Tk::bind('<KP_Enter>',         $edit_command);
#     $canvas->Tk::bind('<Control-o>',        $edit_command);
#     $canvas->Tk::bind('<Control-O>',        $edit_command);
#     $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    my $close_window = sub{
#        my $top = $self->canvas->toplevel;
#        $top->deiconify;
#        $top->raise;
        $self->canvas->toplevel->destroy;
        $self = undef;  # $self will not get DESTROY'd without this, grrr
        };
     $canvas->Tk::bind('<Control-w>',                $close_window);
     $canvas->Tk::bind('<Control-W>',                $close_window);
     $canvas->toplevel->protocol('WM_DELETE_WINDOW', $close_window);

        
    my $top = $canvas->toplevel;
    my $button_frame = $top->Frame->pack(-side => 'top', -fill => 'x');
    my $open = $button_frame->Button(
        -text       => 'Open',
        -command    => sub {
            unless ($self->launch_dotter()) {
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

sub subject {
    my( $self, $subj ) = @_;
    
    $self->{'_subject'} = $subj if $subj && $subj->isa("Hum::Sequence::DNA");
    
    return $self->{'_subject'};
}
sub genomic {
    my( $self, $geno ) = @_;
    
    $self->{'_genomic'} = $geno if $geno && $geno->isa("Hum::Sequence::DNA");

    return $self->{'_genomic'};
}
sub default_start {
    my( $self, $start ) = @_;
    
    $self->{'_d_start'} ||= $start if $start;
    
    return $self->{'_d_start'};
}
sub default_end {
    my( $self, $end ) = @_;
    
    $self->{'_d_end'} ||= $end if $end;

    return $self->{'_d_end'};
}
sub start{
    my( $self, $start ) = @_;
    my $default         = $self->default_start($start) if $start;
    
}
sub end{
    my( $self, $end ) = @_;
    my $default       = $self->default_end($end) if $end;
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}


sub launch_dotter{
    
}

sub draw {
    my( $self ) = @_;
    
     my $font    = $self->font;
     my $size    = $self->font_size;
     my $canvas  = $self->canvas;

     my $font_def = [$font,       $size, 'bold'];
     my $helv_def = ['Helvetica', $size, 'normal'];

#     my $row_height = int $size * 1.5;
#     my $x = $size;
#     for (my $i = 0; $i < @$ss_list; $i++) {
#         my $set = $ss_list->[$i];
#         my $row = $i + 1;
#         my $y = $row_height * $row;
         $canvas->createText(
             50, 50,
             -text   => $self->subject()->name(),
             -font   => $font_def,
             -anchor => 'nw',
             -tags   => ["grrr"],
             );
#     }
    
#     $x = ($canvas->bbox('SetName'))[2] + ($size * 2);
#     for (my $i = 0; $i < @$ss_list; $i++) {
#         my $set = $ss_list->[$i];
#         my $row = $i + 1;
#         my $y = $row_height * $row;
#         $canvas->createText(
#             $x, $y,
#             -text   => $set->description,
#             -font   => $helv_def,
#             -anchor => 'nw',
#             -tags   => ["row=$row", 'SetDescription', 'SequenceSet=' . $set->name],
#             );
#     }
    
#     $x = $size;
#     my $max_x = ($canvas->bbox('SetDescription'))[2];
#     for (my $i = 0; $i < @$ss_list; $i++) {
#         my $set = $ss_list->[$i];
#         my $row = $i + 1;
#         my $y = $row_height * $row;
#         my $rec = $canvas->createRectangle(
#             $x, $y, $max_x, $y + $size,
#             -fill       => undef,
#             -outline    => undef,
#             -tags   => ["row=$row", 'SetBackground', 'SequenceSet=' . $set->name],
#             );
#         $canvas->lower($rec, "row=$row");
#     }
    
    warn Dumper($self->subject);
    warn Dumper($self->genomic);
    $self->fix_window_min_max_sizes;
}


sub write_files{
    my ($self) = @_;
    # This will use jgrg's TempFile module.
    # pick file names
    my $subj_temp_name;
    my $geno_temp_name;
    # get sequences 
    # my $subj_seq = $self->subject->fasta_string();
    # my $gen_subs = $self->genomic->sub_sequence($self->start, $self->end);
    # my $geno_seq = $gen_subs->fasta_string();
    # write files full of sequence.
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

