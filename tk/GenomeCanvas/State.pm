
### GenomeCanvas::State

package GenomeCanvas::State;

use strict;
use Carp;

sub new_State {
    my( $self ) = @_;
    
    $self->{'_state_hash'} = {};
    return $self->{'_state_hash'};
}

sub add_State {
    my( $self, $state ) = @_;
    
    $self->{'_state_hash'} = $state;
}

sub state {
    my( $self ) = @_;
    
    return $self->{'_state_hash'};
}

sub canvas {
    my( $self, $canvas ) = @_;
    
    if ($canvas) {
        confess("Not a Tk::Canvas object '$canvas'")
            unless ref($canvas) and $canvas->isa('Tk::Canvas');
        $self->{'_state_hash'}{'_canvas'} = $canvas;
    }
    return $self->{'_state_hash'}{'_canvas'};
}

sub y_offset {
    my( $self, $y_offset ) = @_;
    
    if (defined $y_offset) {
        $self->{'_state_hash'}{'_y_offset'} = $y_offset;
    }
    return $self->{'_state_hash'}{'_y_offset'};
}

sub font_size {
    my( $self, $font_size ) = @_;
    
    if ($font_size) {
        $self->{'_state_hash'}{'_font_size'} = $font_size;
    }
    return $self->{'_state_hash'}{'_font_size'} || 12;
}

sub residues_per_pixel {
    my( $self, $scale ) = @_;
    
    if ($scale) {
        $self->{'_state_hash'}{'_residues_per_pixel'} = $scale;
    }
    return $self->{'_state_hash'}{'_residues_per_pixel'} || 2000;
}

sub bbox_union {
    my( $self, $bb1, $bb2 ) = @_;
    
    my @new = @$bb1;
    $new[0] = $bb2->[0] if $bb2->[0] < $bb1->[0];
    $new[1] = $bb2->[1] if $bb2->[1] < $bb1->[1];
    $new[2] = $bb2->[2] if $bb2->[2] > $bb1->[2];
    $new[3] = $bb2->[3] if $bb2->[3] > $bb1->[3];
    return @new;
}

sub expand_bbox {
    my( $self, $bbox, $pad ) = @_;
    
    $bbox->[0] -= $pad;
    $bbox->[1] -= $pad;
    $bbox->[2] += $pad;
    $bbox->[3] += $pad;
}

1;

__END__

=head1 NAME - GenomeCanvas::State

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

