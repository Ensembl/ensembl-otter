
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

1;

__END__

=head1 NAME - GenomeCanvas::State

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

