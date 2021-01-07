=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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


### GenomeCanvas

package GenomeCanvas;


use strict;
use warnings;
use Carp;
use Tk;
use GenomeCanvas::Band;
use GenomeCanvas::State;
use CanvasWindow;

use vars qw{@ISA};
@ISA = ('GenomeCanvas::State', 'CanvasWindow');

sub new {
    my( $pkg, $tk ) = @_;
    
    my $gc = $pkg->SUPER::new($tk);
    $gc->new_State;
    
    return $gc;
}

sub band_padding {
    my( $gc, $pixels ) = @_;
    
    if ($pixels) {
        $gc->{'_band_padding'} = $pixels;
    }
    return $gc->{'_band_padding'} || $gc->font_size * 2;
}

sub add_Band {
    my( $gc, $band ) = @_;
    
    $band->add_State($gc->state);
    $band->canvas($gc->canvas);
    push(@{$gc->{'_band_list'}}, $band);

    return;
}

sub band_list {
    my( $gc ) = @_;
    
    return @{$gc->{'_band_list'}};
}

sub render {
    my( $gc ) = @_;
    
    $gc->delete_all_bands;
    
    my $canvas = $gc->canvas;
    my $y_offset = 0;
    my $c = 0;
    my @band_list = $gc->band_list;
    for (my $i = 0; $i < @band_list; $i++) {
        my $band = $band_list[$i];
        print STDERR scalar(localtime), " Rendering a ", ref($band), "\n";
        my $tag = "$band-$i";
        if ($c > 0) {
            # Increase y_offset by the amount
            # given by band_padding
            $y_offset += $gc->band_padding;
        }
        $gc->band_tag($band, $tag);
        #warn "Rendering band '$tag' with offset $y_offset\n";
        
        $gc->y_offset($y_offset);
        $band->tags($tag);
        $band->render;
        $band->draw_titles if $band->can('draw_titles');

        #warn "[", join(',', $canvas->bbox($tag)), "]\n";

        # Move the band to the correct position if it
        # drew itself somewhere else
        $gc->draw_band_outline($band);
        my $actual_y = ($canvas->bbox($tag))[1] || $y_offset;
        if ($actual_y < $y_offset) {
            my $y_move = $y_offset - $actual_y;
            $canvas->move($tag, 0, $y_move);
        }

        #warn "[", join(',', $canvas->bbox($tag)), "]\n";

        $y_offset = ($canvas->bbox($tag))[3];
        $gc->y_offset($y_offset);
        $c++;

    }
    #print STDERR scalar(localtime), " Done rendering\n";

    return;
}

sub draw_band_outline {
    my( $gc, $band ) = @_;
    
    my $canvas = $gc->canvas;
    my @tags = $band->tags;
    my @rect = $canvas->bbox(@tags)
        #or confess "Can't get bbox for tags [@tags]";
        or warn "Nothing drawn for [@tags]" and return;
    my $r = $canvas->createRectangle(
        @rect,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );
    $canvas->lower($r, 'all');

    return;
}

sub delete_all_bands {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;
    foreach my $band ($gc->band_list) {
        my $tag = $gc->band_tag($band);
        $canvas->delete($tag);
    }

    return;
}

sub band_tag {
    my( $gc, $band, $tag ) = @_;
    
    confess "Missing argument: no band" unless $band;
    
    if ($tag) {
        $gc->{'_band_tag_map'}{$band} = $tag;
    }
    return $gc->{'_band_tag_map'}{$band};
}

sub zoom {
    my( $gc, $zoom ) = @_;
    
    my $rpp = $gc->residues_per_pixel;
    my $canvas = $gc->canvas;
    
    # Calculate the coordinate of the centre of the view
    my $scroll_ref = $canvas->cget('scrollregion')
        or confess "No scrollregion";
    my ($x1, $y1, $x2, $y2) = @$scroll_ref;

    # center on x axis
    my @x_view = $canvas->xview;
    my $x_view_center_fraction = $x_view[0] + (($x_view[1] - $x_view[0]) / 2);
    my $x_view_center_coord = $x1 + (($x2 - $x1) * $x_view_center_fraction);   

    # center on y axis
    my @y_view = $canvas->yview;
    my $y_view_center_fraction = $y_view[0] + (($y_view[1] - $y_view[0]) / 2);
    my $y_view_center_coord = $y1 + (($y2 - $y1) * $y_view_center_fraction);

    # Calculate the new number of residues per pixel
    my( $new_rpp );
    if ($zoom > 0) {
        $new_rpp = $rpp / $zoom;
    }
    elsif ($zoom < 0) {
        $zoom *= -1;
        $new_rpp = $rpp * $zoom;
    }
    else {
        return;
    }
    warn "rpp=$new_rpp\n";
    
    my $x_zoom_factor = $rpp / $new_rpp;
    #$canvas->scale('all', $x_view_center_coord, $y_view_center_coord, $x_zoom_factor, 1);
    $canvas->scale('all', 0,0, $x_zoom_factor, 1);
    
    $gc->residues_per_pixel($new_rpp);
    $gc->fix_window_min_max_sizes;

    return;
}

1;

__END__

=head1 NAME - GenomeCanvas

=head1 DESCRIPTION

GenomeCanvas is a container object for a
Tk::Canvas object, and one or many
GenomeCanvas::Band objects.

Each GenomeCanvas::Band object implements the
render method.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

