=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### KaryotypeWindow::Chromosome

package KaryotypeWindow::Chromosome;

use strict;
use warnings;
use Carp;
use KaryotypeWindow::Band;
use KaryotypeWindow::Graph;

sub new {
    my ( $pkg ) = @_;

    return bless {}, $pkg;
}

sub name {
    my ( $self, $name ) = @_;

    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub draw {
    my ( $self, $kw, $x, $y ) = @_;

    my $save_y = $y;

    my $scale = $kw->Mb_per_pixel;
    foreach my $band ( $self->get_all_Bands ) {
        $band->draw( $self, $kw, $x, $y );
        $y += $band->height($kw);
    }

    my ( $band_first, $band_last ) = $self->get_first_and_last_Bands;
    my $canvas = $kw->canvas;
    my $outline = $canvas->createPolygon(
        $self->get_outline_coordinates,
        -fill => undef,
        -outline   => 'black',
        -smooth    => 1,
        -joinstyle => 'round',
    );
    
    my $font_size = $kw->font_size;
    $canvas->createText(
        $x + $self->chr_width($kw) / 2, $y + $font_size,
        -anchor => 'n',
        -text => $self->name,
        -font => [ 'Helvetica', $font_size, 'bold' ],
    );
    
    my $max_y = $band_last->end;
    my $pad = $self->pad($kw);
    my $graph_x = $x + $self->chr_width($kw) + $self->pad($kw);
    foreach my $graph ($self->get_all_Graphs) {
        $graph->max_y($max_y);
        $graph->draw($kw, $graph_x, $save_y);
        $graph_x += $pad + $graph->width;
    }

    return;
}

sub height {
    my( $self, $kw ) = @_;

    my ( $band_first, $band_last ) = $self->get_first_and_last_Bands;
    my $length = ( $band_last->end - $band_first->start + 1 ) / 1_000_000;
    return(($kw->font_size * 2) + ($length / $kw->Mb_per_pixel));
}

sub pad {
    my( $self, $kw ) = @_;

    return $kw->pad / 4;
}

sub chr_width {
    my( $self, $kw ) = @_;

    return $kw->Mb_per_pixel * 15;
}

sub width {
    my( $self, $kw ) = @_;
    
    my @graphs = $self->get_all_Graphs;
    my $graph_width = 0;
    my $pad = $self->pad($kw);
    foreach my $graph (@graphs) {
        $graph_width += $pad + $graph->width;
    }
    #warn sprintf"graph_width = %d  chr_width = %d\n",
    #    $graph_width, $self->chr_width($kw);
    return $graph_width + $self->chr_width($kw);
}

sub get_outline_coordinates {
    my ($self) = @_;

    my @bands = $self->get_all_Bands;
    my (@coords);
    foreach my $b (@bands) {
        push ( @coords, $b->right_coordinates ) unless $b->is_rectangular;
    }
    foreach my $b ( reverse @bands ) {
        push ( @coords, $b->left_coordinates ) unless $b->is_rectangular;
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
    $bands[-1]->is_last(1);

    return;
}

sub get_first_and_last_Bands {
    my ($self) = @_;

    my @bands = $self->get_all_Bands;
    return @bands[ 0, $#bands ];
}

sub get_all_Graphs {
    my ($self) = @_;

    if ( my $lst = $self->{'_Graph_list'} ) {
        return @$lst;
    }
    else {
        return;
    }
}

sub add_Graph {
    my ( $self, $Graph ) = @_;

    confess "Missing Graph argument" unless $Graph;
    my $lst = $self->{'_Graph_list'} ||= [];
    push ( @$lst, $Graph );

    return;
}

sub new_Graph {
    my ( $self, $class ) = @_;

    $class ||= 'KaryotypeWindow::Graph';
    my $Graph = $class->new;
    $self->add_Graph($Graph);
    return $Graph;
}

sub get_all_Bands {
    my ($self) = @_;

    if ( my $lst = $self->{'_Band_list'} ) {
        return @$lst;
    }
    else {
        return;
    }
}

sub add_Band {
    my ( $self, $band ) = @_;

    confess "Missing Band argument" unless $band;
    my $lst = $self->{'_Band_list'} ||= [];
    push ( @$lst, $band );

    return;
}

sub new_Band {
    my ( $self, $class ) = @_;

    $class ||= 'KaryotypeWindow::Band';
    my $band = $class->new;
    $self->add_Band($band);
    return $band;
}

1;

__END__

=head1 NAME - KaryotypeWindow::Chromosome

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

