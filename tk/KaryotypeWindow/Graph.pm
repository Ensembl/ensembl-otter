### KaryotypeWindow::Graph

package KaryotypeWindow::Graph;

use strict;
use Carp;
use KaryotypeWindow::Graph::Bin;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub label {
    my( $self, $label ) = @_;
    
    if ($label) {
        $self->{'_label'} = $label;
    }
    return $self->{'_label'} || confess "label not set";
}

sub max_x {
    my( $self, $max_x ) = @_;
    
    if ($max_x) {
        $self->{'_max_x'} = $max_x;
    }
    return $self->{'_max_x'} || confess "max_x not set";
}

sub max_y {
    my( $self, $max_y ) = @_;
    
    if ($max_y) {
        $self->{'_max_y'} = $max_y;
    }
    return $self->{'_max_y'} || confess "max_y not set";
}

sub height {
    my( $self, $kw ) = @_;
    
    return( ($self->max_y / 1_000_000)
        / $kw->Mb_per_pixel );
}

sub width {
    my( $self, $width ) = @_;
    
    if ($width) {
        $self->{'_width'} = $width;
    }
    return $self->{'_width'} || 100;
}

sub scale {
    my( $self ) = @_;
    
    return $self->max_x / $self->width;
}

sub get_all_Bins {
    my ($self) = @_;

    if ( my $lst = $self->{'_Bin_list'} ) {
        return @$lst;
    }
    else {
        return;
    }
}

sub add_Bin {
    my ( $self, $Bin ) = @_;

    confess "Missing Bin argument" unless $Bin;
    my $lst = $self->{'_Bin_list'} ||= [];
    push ( @$lst, $Bin );
}

sub new_Bin {
    my ( $self, $class ) = @_;

    $class ||= 'KaryotypeWindow::Bin';
    my $Bin = $class->new;
    $self->add_Bin($Bin);
    return $Bin;
}

sub draw {
    my ( $self, $kw, $x, $y ) = @_;

    warn "args = [$self, $kw, $x, $y]";

    my @coords = ($x, $y, $x + $self->width, $y + $self->height($kw));
    $kw->canvas->createRectangle(
        @coords,
        -fill       => undef,
        -outline    => 'red',
        );

    #my $chr = $self->chromosome;

    #my $x1 = $x + $chr->width + 8;
    #my $y1 = $y;

    #my $x2 = $x1;
    #my $y2 = $y1 + $chr->height;

    #$self->draw_histogram( $kw, $x1, $y1 );

    #$kw->{'_canvas'}->createLine(
    #    $x1, $y1, $x2, $y2, -fill => 'black',
    #    -width => 0.25,
    #);

}

sub draw_histogram {
    my ( $self, $kw, $x1, $y1 ) = @_;

    my $chr = $self->chromosome;

    my $chr_name = $chr->name;

    my $data   = $kw->data;
    my @values = @{ %$data->{$chr_name} };

    my $height = $chr->height;

    my $inc = 2;
    my $x   = 0;
    for ( my $i = 1 ; $i <= $height ; $i += $inc ) {
        my $x_val = $values[$x];

        my $x2 = $x1 + $x_val / 2 + 0.5;
        my $y2 = $y1 + $inc;

        if ( $x_val > 0 ) {
            $kw->{'_canvas'}->createRectangle(
                $x1, $y1, $x2, $y2, -fill => '#cc3333',
                -outline => '#cc3333',
                -width   => 0.25,
            );
        }
        $y1 = $y2;
        $x++;
    }
}


1;

__END__

=head1 NAME - KaryotypeWindow::Graph

=head1 AUTHOR

Stephen Keenan B<email> keenan@sanger.ac.uk

