
### KaryotypeWindow::Chromosome

package KaryotypeWindow::Chromosome;

use strict;
use Carp;
use KaryotypeWindow::Band;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub draw {
    my( $self, $canvas, $x, $y ) = @_;
    
    my $scale = $self->Mb_per_pixel;
    foreach my $band ($self->get_all_Bands) {
        $band->Mb_per_pixel($scale);
        $band->draw($self, $canvas, $x, $y);
        $y += $band->height;
    }
    
    my ($first, $last) = $self->get_first_and_last_Bands;
    $canvas->createPolygon(
        $first->right_coordinates, $last->right_coordinates,
        $last->left_coordinates, $first->left_coordinates,
        -fill    => undef,
        -outline => 'black',
        -smooth  => 1,
        );
}

sub get_outline_coordinates {
    my( $self ) = @_;
    
    my @bands = $self->get_all_Bands;
    my( @coords );
    foreach my $b (@bands) {
        push(@coords, $b->right_coordinates)
            unless $b->is_rectangular;
    }
    foreach my $b (reverse @bands) {
        push(@coords, $b->left_coordinates)
            unless $b->is_rectangular;
    }
    
    return @coords;
}

sub set_initial_and_terminal_bands {
    my( $self ) = @_;
    
    my @bands = $self->get_all_Bands;
    foreach my $band (@bands) {
        $band->is_first(0);
        $band->is_last(0);
    }
    $bands[0]->is_first(1);
    $bands[$#bands]->is_last(1);

}

sub get_first_and_last_Bands {
    my( $self ) = @_;
    
    my @bands = $self->get_all_Bands;
    return @bands[0, $#bands];
}

sub width {
    my( $self ) = @_;
    
    return $self->Mb_per_pixel * 15;
}

sub get_all_Bands {
    my( $self ) = @_;
    
    if (my $lst = $self->{'_Band_list'}) {
        return @$lst;
    } else {
        return;
    }
}

sub add_Band {
    my( $self, $band ) = @_;
    
    confess "Missing Band argument" unless $band;
    my $lst = $self->{'_Band_list'} ||= [];
    push(@$lst, $band);
}

sub new_Band {
    my( $self, $class ) = @_;
    
    $class ||= 'KaryotypeWindow::Band';
    my $band = $class->new;
    $self->add_Band($band);
    return $band;
}

sub Mb_per_pixel {
    my( $self, $Mb_per_pixel ) = @_;
    
    if ($Mb_per_pixel) {
        $self->{'_Mb_per_pixel'} = $Mb_per_pixel;
    }
    return $self->{'_Mb_per_pixel'} || confess "Scale not set";
}


1;

__END__

=head1 NAME - KaryotypeWindow::Chromosome

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

