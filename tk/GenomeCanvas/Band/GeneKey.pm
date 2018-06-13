=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::Band::GeneKey

package GenomeCanvas::Band::GeneKey;

use strict;

use Carp;
use base 'GenomeCanvas::Band';

sub render {
    my ($self) = @_;

    my $rpp                 = $self->residues_per_pixel;
    my $y                   = $self->y_offset;
    my @tags                = $self->tags;
    my $canvas              = $self->canvas;
    my $font_size           = $self->font_size;
    my $ctg_name            = $self->title;
    my $max_rows            = $self->max_rows;
    my $style_collection    = $self->styles->{'style'};
    
    my $pad = 2 * $font_size;
    my $line_width  = $font_size / 5;
    my $half_height = $font_size / 2;
    
    my $x = 0;
    my $row = 0;
    foreach my $label (
        sort {
              $style_collection->{$a}{'file_position'}
          <=> $style_collection->{$b}{'file_position'}
        } keys %$style_collection
      )
    {
        $row++;
        my $style = $style_collection->{$label};
        my ($x1,$y1, $x2,$y2) = ($x,$y, $x + $font_size, $y + $font_size);
        
        if ($style->{'type'} eq 'REP') {
            my $y1 = $y1 + ($font_size / 8);
            my $y2 = $y2 - ($font_size / 8);

            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -outline => undef,
                -fill    => $style->{'fill'},
                -tags    => [@tags],
            );
            $canvas->createLine(
                $x1, $y1, $x2, $y1,
                -width  => 1.5 * $line_width,
                -fill   => $style->{'outline'},
                -tags   => [@tags],
            );
            $canvas->createLine(
                $x1, $y2, $x2, $y2,
                -width  => 1.5 * $line_width,
                -fill   => $style->{'outline'},
                -tags   => [@tags],
            );
        } else {
            $canvas->createOval(
                $x1,$y1, $x2,$y2,
                -fill       => $style->{'fill'},
                -outline    => $style->{'outline'},
                -width      => $line_width,
                -tags       => [@tags],
                );
        }
        
        $x1 = $x2 + $font_size;
        $y1 += $half_height;
        
        $canvas->createText(
            $x1,$y1,
            -text   => $label,
            -anchor => 'w',
            -font   => ['helvetica', $font_size, 'bold'],
            -tags       => [@tags],
            );
        
        # Do we start a new column?
        if ($row % $max_rows) {
            $y += $font_size + $pad;
        } else {
            $y = $self->y_offset;
            my $max_x = ($self->band_bbox)[2];
            $x = $max_x + (2 * $pad);
        }
    }
    
    $x = 0;
    $y = ($self->band_bbox)[3] + (2 * $pad);
    
    my ($x1,$y1, $x2,$y2) = ($x,$y, $x + $font_size, $y + $font_size);

    ### Yuk. Copy / paste code ahead:
    
    push(@tags, 'lastrow');
    # Repeat
    {
        my $y1 = $y1 + ($font_size / 8);
        my $y2 = $y2 - ($font_size / 8);

        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -outline => undef,
            -fill    => '#cccccc',
            -tags    => [@tags],
            );
        $canvas->createLine(
            $x1, $y1, $x2, $y1,
            -width  => 1.5 * $line_width,
            -fill   => 'black',
            -tags   => [@tags],
            );
        $canvas->createLine(
            $x1, $y2, $x2, $y2,
            -width  => 1.5 * $line_width,
            -fill   => 'black',
            -tags   => [@tags],
            );
        $x1 = $x2 + $font_size;
        $y1 += $half_height;
        $canvas->createText(
            $x1,$y1,
            -text   => 'Repeat',
            -anchor => 'w',
            -font   => ['helvetica', $font_size, 'bold'],
            -tags   => [@tags],
            );
    }
    
    $x = ($canvas->bbox('lastrow'))[2] + (2 * $pad);
    ($x1,$y1, $x2,$y2) = ($x,$y, $x + $font_size, $y + $font_size);

    # Active gene
    $canvas->createPolygon(
        $x1, $y1,
        $x2 - $half_height, $y1,
        $x2, $y1 + ($font_size / 2),
        $x2 - $half_height, $y2,
        $x1, $y2,
        -outline    => 'black',
        -fill       => '#cccccc',
        -width      => $line_width,
        -tags       => [@tags],
        );
    $x1 = $x2 + $font_size;
    $y1 += $half_height;
    $canvas->createText(
        $x1,$y1,
        -text   => 'Gene',
        -anchor => 'w',
        -font   => ['helvetica', $font_size, 'bold'],
        -tags   => [@tags],
        );
    
    $x = ($canvas->bbox('lastrow'))[2] + (2 * $pad);
    ($x1,$y1, $x2,$y2) = ($x,$y, $x + $font_size, $y + $font_size);
    
    # Pseudogene
    $canvas->createOval(
        $x1,$y1, $x2,$y2,
        -outline    => 'black',
        -fill       => '#cccccc',
        -width      => $line_width,
        -tags       => [@tags],
        );
    $x1 = $x2 + $font_size;
    $y1 += $half_height;
    $canvas->createText(
        $x1,$y1,
        -text   => 'Pseudogene',
        -anchor => 'w',
        -font   => ['helvetica', $font_size, 'bold'],
        -tags   => [@tags],
        );
    
}

sub styles {
    my ($self, $styles) = @_;

    if ($styles) {
        $self->{'_styles'} = $styles;
    }
    return $self->{'_styles'};
}

sub max_rows {
    my( $self, $max_rows ) = @_;
    
    if ($max_rows) {
        $self->{'_max_rows'} = $max_rows;
    }
    return $self->{'_max_rows'} || 6;
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::GeneKey

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

