
### KaryotypeWindow::Graph::Bin

package KaryotypeWindow::Graph::Bin;

use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub start {
    my( $self, $start ) = @_;
    
    if ($start) {
        $self->{'_start'} = $start;
    }
    return $self->{'_start'};
}

sub end {
    my( $self, $end ) = @_;
    
    if ($end) {
        $self->{'_end'} = $end;
    }
    return $self->{'_end'};
}

sub value {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_value'} = $value;
    }
    return $self->{'_value'};
}


1;

__END__

=head1 NAME - KaryotypeWindow::Graph::Bin

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

