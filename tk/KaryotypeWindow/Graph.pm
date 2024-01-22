=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

### KaryotypeWindow::Graph

package KaryotypeWindow::Graph;

use strict;
use warnings;
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

sub bin_size {
    my( $self, $bin_size ) = @_;
    
    if ($bin_size) {
        $self->{'_bin_size'} = $bin_size;
    }
    return $self->{'_bin_size'};
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

    return;
}

sub new_Bin {
    my ( $self, $class ) = @_;

    $class ||= 'KaryotypeWindow::Graph::Bin';
    my $Bin = $class->new;
    $self->add_Bin($Bin);
    return $Bin;
}

sub color {
    my( $self, $color ) = @_;
    
    if ($color) {
        $self->{'_color'} = $color;
    }
    return $self->{'_color'} || '#cc3333';
}


sub draw {
    my ( $self, $kw, $x, $y ) = @_;

    my $scale  = $kw->Mb_per_pixel * 1_000_000;
    my $canvas = $kw->canvas;

    my $max_x  = $self->max_x;
    my $max_y  = $self->max_y;
    my $color  = $self->color;
    my $width  = $self->width;

    # Draw axes
    $canvas->createRectangle(
        $x,$y, $x + $width, $y + $self->height($kw),
        -fill       => undef,
        -outline    => 'black',
        -width      => 0.25,
        );

    # Draw bars in front of axes, so that small bars
    # aren't hidden my the axes.
    foreach my $bin ($self->get_all_Bins) {
        my $y1 = $y + ($bin->start / $scale);
        my $y2 = $y + ($bin->end   / $scale);
        my $x2 = $x + ($width * ($bin->value / $max_x));
        $canvas->createRectangle(
            $x, $y1, $x2, $y2,
            -fill       => $color,
            -outline    => $color,
            -width      => 0.5,
            -tags       => ['histogram_bar'],
            );
    }

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

    return;
}

sub draw_histogram {
    my ( $self, $kw, $x1, $y1 ) = @_;

    my $chr = $self->chromosome;

    my $chr_name = $chr->name;

    my $data   = $kw->data;
    my @values = @{ $data->{$chr_name} };

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

    return;
}


1;

__END__

=head1 NAME - KaryotypeWindow::Graph

=head1 AUTHOR

Stephen Keenan B<email> keenan@sanger.ac.uk

