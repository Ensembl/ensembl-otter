
### CanvasWindow::SequenceNotes

package CanvasWindow::SequenceNotes;

use strict;
use Carp;
use base 'CanvasWindow';

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);

    my $top = $self->canvas->toplevel;
    my $close_window = sub{ $top->withdraw };
    $top->protocol('WM_DELETE_WINDOW', $close_window);
    $top->bind('<Control-w>', $close_window);
    $top->bind('<Control-W>', $close_window);

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

sub SequenceSet {
    my( $self, $SequenceSet ) = @_;
    
    if ($SequenceSet) {
        $self->{'_SequenceSet'} = $SequenceSet;
    }
    return $self->{'_SequenceSet'};
}

sub SequenceSetChooser {
    my( $self, $SequenceSetChooser ) = @_;
    
    if ($SequenceSetChooser) {
        $self->{'_SequenceSetChooser'} = $SequenceSetChooser;
    }
    return $self->{'_SequenceSetChooser'};
}

sub draw {
    my( $self ) = @_;
    
    my $ss = $self->SequenceSet;
    $self->SequenceSetChooser->DataSet->fetch_all_CloneSequences_for_SequenceSet($ss);
    my $cs_list = $ss->get_all_CloneSequences;
    my $font    = $self->font;
    my $size    = $self->font_size;
    my $canvas  = $self->canvas;

    my $font_def = [$font,       $size, 'bold'];
    my $helv_def = ['Helvetica', $size, 'normal'];
    my $row_height = int $size * 1.5;
    my $x = $size;
    my $gaps = 0;
    for (my $i = 0; $i < @$cs_list; $i++) {
        my $row = $i + $gaps + 1;
        my $cs = $cs_list->[$i];
        unless ($i == 0) {
            my $last = $cs_list->[$i - 1];
            my $gap = $cs->chr_start - $last->chr_end - 1;
            if ($gap > 0) {
                ### Draw gap
                $gaps++;
                $row++;
            }
        }
        
        my $y = $row * $row_height;
        my $name = $cs->accession .'.'. $cs->sv;
        my $text = sprintf "%4d  %-s", $row, $name;
        $canvas->createText(
            $x, $y,
            -anchor => 'nw',
            -font   => $font_def,
            -text   => $text,
            -tags   => ["row=$row", "CloneSequence=$name"],
            );
    }
    $self->fix_window_min_max_sizes;
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

