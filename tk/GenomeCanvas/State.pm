
### GenomeCanvas::State

package GenomeCanvas::State;

use strict;
use Carp;

sub new_State {
    my( $self ) = @_;
    
    $self->{'_state_hash'} = {
        '_frame' => [0,0,0,0],
        };
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

sub frame {
    my( $self, @bbox ) = @_;
    
    if (@bbox) {
        confess "frame must have 4 elements, got: (@bbox)" 
            unless @bbox == 4;
        $self->{'_state_hash'}{'_frame'} = [@bbox];
    }
    return @{$self->{'_state_hash'}{'_frame'}};
}

sub residues_per_pixel {
    my( $self, $scale ) = @_;
    
    if ($scale) {
        $self->{'_residues_per_pixel'} = $scale;
    }
    return $self->{'_residues_per_pixel'} || 2000;
}

sub frame_union {
    my( $self, @new_bbox ) = @_;
    
    my @bbox = $self->frame;
    $bbox[0] = $new_bbox[0] if $new_bbox[0] < $bbox[0];
    $bbox[1] = $new_bbox[1] if $new_bbox[1] < $bbox[1];
    $bbox[2] = $new_bbox[2] if $new_bbox[2] > $bbox[2];
    $bbox[3] = $new_bbox[3] if $new_bbox[3] > $bbox[3];
    return $self->frame(@bbox);
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

