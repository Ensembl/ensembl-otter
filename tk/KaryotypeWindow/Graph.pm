### KaryotypeWindow::Graph

package KaryotypeWindow::Graph;

use strict;
use Carp;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub draw {
    my ( $self, $kw, $x, $y ) = @_;

    my $chr = $self->chromosome;

    my $x1 = $x + $chr->width + 8;
    my $y1 = $y;

    my $x2 = $x1;
    my $y2 = $y1 + $chr->height;

    $self->draw_histogram( $kw, $x1, $y1 );

    $kw->{'_canvas'}->createLine(
        $x1, $y1, $x2, $y2, -fill => 'black',
        -width => 0.25,
    );

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

sub chromosome {
    my ( $self, $chromosome ) = @_;

    if ($chromosome) {
        $self->{'_chromosome'} = $chromosome;

    }

    return $self->{'_chromosome'};
}

1;

__END__

=head1 NAME - KaryotypeWindow::Graph

=head1 AUTHOR

Stephen Keenan B<email> keenan@sanger.ac.uk

