
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
    my( $self, $kw, $x, $y ) = @_;
    
    my $save_y = $y;
    
    my $scale = $self->Mb_per_pixel;
    my $canvas = $kw->canvas;
    foreach my $band ($self->get_all_Bands) {
        $band->Mb_per_pixel($scale);
        $band->draw($self, $canvas, $x, $y);
        $y += $band->height;
    }
    
    my ($first, $last) = $self->get_first_and_last_Bands;
    my $outline = $canvas->createPolygon(
        $self->get_outline_coordinates,
        -fill       => undef,
        -outline    => 'black',
        -smooth     => 1,
        -joinstyle  => 'round',
        );
    
    $canvas->createText(
        $x + $self->width / 2,
        $save_y + $self->height + $kw->pad / 2,
        -anchor => 'n',
        -text   => $self->name,
        -font   => ['Helvetica', $kw->font_size, 'bold'],
        );
}

sub height {
    my( $self ) = @_;
    
    my ($first, $last) = $self->get_first_and_last_Bands;
    my $length = ($last->end - $first->start + 1) / 1_000_000;
    return $length / $self->Mb_per_pixel;
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

