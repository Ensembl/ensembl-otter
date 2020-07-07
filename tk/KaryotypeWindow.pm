=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


### KaryotypeWindow

package KaryotypeWindow;

use strict;
use warnings;
use Carp;
use base 'CanvasWindow';
use KaryotypeWindow::Chromosome;

sub new {
    my $pkg = shift;

    my $self = $pkg->SUPER::new(@_);

    #$self->canvas->DefineBitmap(
    #    'gvar', 4, 1, pack('b4', '..11')
    #    );
    $self->canvas->DefineBitmap( 'gvar', 2, 2, pack( 'b2' x 2, '.1', '1.', ) );

    #$self->canvas->DefineBitmap(
    #    'gcen', 2, 1, pack('b2', '.1')
    #    );
    return $self;
}

sub get_all_Chromosomes {
    my ($self) = @_;

    if ( my $lst = $self->{'_Chromosome_list'} ) {
        return @$lst;
    }
    else {
        return;
    }
}

sub chromosomes_per_row {
    my ( $self, $chromosomes_per_row ) = @_;

    if ($chromosomes_per_row) {
        $self->{'_chromosomes_per_row'} = $chromosomes_per_row;
    }
    return $self->{'_chromosomes_per_row'} || 12;
}

sub add_Chromosome {
    my ( $self, $chr ) = @_;

    confess "Missing Chromosome argument" unless $chr;
    my $lst = $self->{'_Chromosome_list'} ||= [];
    push ( @$lst, $chr );

    return;
}

sub new_Chromosome {
    my ($self) = @_;

    my $chr = KaryotypeWindow::Chromosome->new;
    $self->add_Chromosome($chr);
    return $chr;
}

sub draw {
    my ($self) = @_;

    my $max     = $self->chromosomes_per_row;
    my $chr_set = [];
    my @all_chr_set = ($chr_set);
    foreach my $chr ( $self->get_all_Chromosomes ) {
        push ( @$chr_set, $chr );
        if ( @$chr_set >= $max ) {
            $chr_set = [];
            push ( @all_chr_set, $chr_set );
        }
    }

    my $pad = $self->pad;
    my ( $x, $y ) = ( $pad, $pad );
    foreach my $chr_set (@all_chr_set) {
        next unless @$chr_set;
        $y += $self->draw_chromsome_set( $x, $y, $chr_set );
        $y += $pad;
    }
    
    $self->draw_legend($x, $y);
    $self->canvas->raise('histogram_bar', 'all');

    return;
}

sub draw_legend {
    my( $self, $x, $y ) = @_;
    
    my @graphs = ($self->get_all_Chromosomes)[0]
        ->get_all_Graphs;
    
    my $font_size = $self->font_size;
    my $pad = $self->pad;
    my $canvas = $self->canvas;
    my $font       = ['Helvetica',       $font_size, 'bold'];
    my $small_font = ['Helvetica', 0.8 * $font_size, 'bold'];
    foreach my $graph (@graphs) {
        my $height = $graph->bin_size / (1_000_000 * $self->Mb_per_pixel);
        my $y_off = ($font_size - $height) / 2;
        my $width  = $graph->width;
        $canvas->createLine(
            $x, $y, $x, $y+$font_size,
            -fill       => 'black',
            -width      => 0.25,
            );
        $canvas->createLine(
            $x+$width, $y, $x+$width, $y+$font_size,
            -fill       => 'black',
            -width      => 0.25,
            );
        $canvas->createRectangle(
            $x, $y+$y_off, $x+$width, $y+$y_off+$height,
            -fill       => $graph->color,
            -outline    => $graph->color,
            -width      => 0.5,
            );
        $canvas->createText(
            $x, $y+(1.5*$font_size),
            -anchor => 'n',
            -text   => '0',
            -font   => $small_font,
            );
        $canvas->createText(
            $x+$width, $y+(1.5*$font_size),
            -anchor => 'n',
            -text   => $graph->max_x,
            -font   => $small_font,
            );
        $canvas->createText(
            $x+$width+$font_size, $y,
            -anchor => 'nw',
            -text   => $graph->label,
            -font   => $font,
            -tags   => 'scale_label',
            );
        
        # Move pointer to the right for next label
        $x = ($canvas->bbox('scale_label'))[2] + $pad;
    }

    return;
}

sub draw_chromsome_set {
    my ( $self, $x, $y, $chr_set ) = @_;

    warn sprintf "Drawing set of %d chromsomes\n", scalar @$chr_set;

    my $scale          = $self->Mb_per_pixel;
    my $canvas         = $self->canvas;
    my $pad            = $self->pad;
    my $max_chr_height = 0;
    foreach my $chr (@$chr_set) {
        my $h = $chr->height($self);
        $max_chr_height = $h if $h > $max_chr_height;
    }

    foreach my $chr (@$chr_set) {
        $chr->set_initial_and_terminal_bands;
        my $chr_y = $y + $max_chr_height - $chr->height($self);
        $chr->draw( $self, $x, $chr_y );
        #$canvas->createRectangle(
        #    $x, $chr_y, $x + $chr->width($self), $chr_y + $chr->height($self),
        #    -fill   => undef,
        #    -outline    => 'blue',
        #    );
        $x += $chr->width($self) + $pad;
    }
    return $max_chr_height;
}

sub Mb_per_pixel {
    my ( $self, $Mb_per_pixel ) = @_;

    if ($Mb_per_pixel) {
        $self->{'_Mb_per_pixel'} = $Mb_per_pixel;
    }
    return $self->{'_Mb_per_pixel'} || 1;
}

sub pad {
    my ( $self, $pad ) = @_;

    if ($pad) {
        $self->{'_pad'} = $pad;
    }
    return $self->{'_pad'} || 2 * $self->font_size;
}

sub process_graph_data_file {
    my( $self, $file ) = @_;
    
    my $test_graph = KaryotypeWindow::Graph->new;
    
    open my $data_h, '<', $file or die "Can't read '$file' : $!";
    my $param = {};
    my $data  = {};
    my $bin_size = 0;
    while (<$data_h>) {
        next if /^\s*$/;
        if (/^\s*#/) {
            while (/(\w+)="([^"]+)"/g){
                unless ($test_graph->can($1)) {
                    die "Unknown graph property '$1' in file '$file'\n";
                }
                $param->{$1} = $2;
            }
            while (/(\w+)=(\S+)/g){
                next if $param->{$1};
                unless ($test_graph->can($1)) {
                    die "Unknown graph property '$1' in file '$file'\n";
                }
                $param->{$1} = $2;
            }
            next;
        }
        my ($chr, $start, $end, $value) = split;
        my $this_bin_size = $end - $start + 1;
        if ($bin_size and $this_bin_size != $bin_size) {
            warn "data point in '$file' with bin_size=$this_bin_size instead of $bin_size";
        } else {
            $bin_size = $this_bin_size;
        }
        my $chr_data = $data->{$chr} ||= [];
        push(@$chr_data, [$start, $end, $value]);
    }
    close $data_h or die "Error reading data from '$file' : $!";
    
    foreach my $chr ($self->get_all_Chromosomes) {
        my $graph = $chr->new_Graph;
        $graph->bin_size($bin_size);
        while (my ($method, $value) = each %$param) {
            $graph->$method($value);
        }
        my $chr_name = $chr->name;
        if (my $data = delete($data->{$chr_name})) {
            foreach my $d (@$data) {
                my( $start, $end, $value ) = @$d;
                next unless $value;     # Don't bother with zeros
                my $bin = $graph->new_Bin;
                $bin->start($start);
                $bin->end($end);
                $bin->value($value);
            }
        } else {
            warn "No data for chromosome '$chr_name' in '$file'\n";
        }
    }
    
    if (my @none_such = sort keys %$data) {
        warn "No such chromosomes:\n", map { "  $_\n" } @none_such;
    }

    return;
}



1;




__END__

=head1 NAME - KaryotypeWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

