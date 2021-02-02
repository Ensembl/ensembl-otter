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


### GenomeCanvas::Band::TilingPath

package GenomeCanvas::Band::TilingPath;

use strict;
use Carp;
use GenomeCanvas::Band;
use CanvasWindow::Utils 'expand_bbox';

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');


sub new {
    my( $pkg, $vc ) = @_;
    
    confess "usage new(<virtual_contig>)" unless $vc;
    my $band = bless {}, $pkg;
    $band->virtual_contig($vc);
    $band->show_labels(1);
    $band->gold(1);
    return $band;
}

sub gold {
    my( $band, $flag ) = @_;
    
    if (defined $flag) {
        $band->{'_show_gold'} = $flag;
    }
    return $band->{'_show_gold'};
}

sub name_morpher {
    my( $band, $morpher ) = @_;
    
    if ($morpher) {
        confess "Not a subroutine ref '$morpher'"
            unless ref($morpher) eq 'CODE';
        $band->{'_name_morpher'} = $morpher;
    }
    return $band->{'_name_morpher'};
}

sub rectangle_height {
    my ($band, $height) = @_;
    if ($height) {
	$band->{'_tp_rec_height'} = $height;
    }

    return $band->{'_tp_rec_height'} || $band->font_size * 10 / 12;
}


sub rectangle_border {
    my ($band, $border) = @_;
    if ($border) {
	$band->{'_tp_rec_border'} = $border;
    }

    return $band->{'_tp_rec_border'} || $band->font_size / 12;
}


sub render {
    my( $band ) = @_;
    
    my $canvas         = $band->canvas;
    my $vc             = $band->virtual_contig;
    my $y_dir          = $band->tiling_direction;
    my $rpp            = $band->residues_per_pixel;
    my $y_offset       = $band->y_offset;
    my @tags           = $band->tags;
    my $font_size      = $band->font_size;
    my $name_morpher   = $band->name_morpher;

    if ($y_dir == -1) {
        # We have to build above the other bands
        my $y_top = ($canvas->bbox('all'))[1] || 0;
        $y_offset = $y_top - 100;
    }

    my $map_contig_count = 0;
    my $rectangle_height = $band->rectangle_height;
    my $rectangle_border = $band->rectangle_border;
    my $nudge_distance = ($rectangle_height + 1) * $y_dir;
    my $text_nudge_flag = 0;
    #foreach my $map_c (@{$vc->get_tiling_path}) {
    foreach my $seg (@{$vc->project('contig')}) {
        my $contig = $seg->to_Slice;
        #print STDERR ".";
        $map_contig_count++;
        #my $start     = $map_c->assembled_start;
        #my $end       = $map_c->assembled_end;
        my $start = $seg->from_start;
        my $end   = $seg->from_end;

        #my $raw_start = $map_c->component_start;
        #my $raw_end   = $map_c->component_end;
	    #my $raw_ori = $map_c->component_ori;
        my $raw_start = $contig->start;
        my $raw_end   = $contig->end;
        my $raw_ori   = $contig->strand;

	    #my $contig    = $map_c->component_Seq;
        my $length = $contig->seq_region_length;
	    my $name = $contig->seq_region_name;
        if ($name_morpher) {
            $name = &$name_morpher($name);
        }
        my $group = "$tags[0]::$name";
        #printf STDERR "%-10s  %2d %6d %6d %6d  %10d %10d\n", $name, $raw_ori, $raw_start, $raw_end, $length, $start, $end;

        my( $left_overhang, $right_overhang );
	    if ($raw_ori == 1) {
            $left_overhang  = $raw_start - 1;
            $right_overhang = $length - $raw_end;
        } else {
            $left_overhang  = $length - $raw_end;
            $right_overhang = $raw_start - 1;
        }

        my $x1 = ($start - $left_overhang + 1) / $rpp;
        my $x2 = ($end   + $right_overhang)    / $rpp;
        
        my @rectangle = ($x1, $y_offset, $x2, $y_offset + $rectangle_height);
        my $rec = $canvas->createRectangle(
            @rectangle,
            -fill => 'black',
            -outline => undef,
            -tags => [@tags, 'contig', $group],
            );
        
        if ($band->gold) {
            # Render golden path segment in gold
            my $gold = $canvas->createRectangle(
                ($start / $rpp), $rectangle[1] + $rectangle_border,
                ($end / $rpp),   $rectangle[3] - $rectangle_border,
                -fill => 'gold',
                -outline => undef,
                -tags => [@tags, 'contig_gold', $group],
                );
        }

        if ($band->show_labels) {
            
            my $label_space = 1;
            my( $anchor, $y1 );
            if ($y_dir == 1) {
                $anchor = 'nw';
                $y1 = $y_offset + $rectangle_height + $label_space;
            } else {
                $anchor = 'sw';
                $y1 = $y_offset + (-1 * $label_space);
            }
            
            my $label = $canvas->createText(
                $x1, $y1,
                -text => $name,
                -font => ['helvetica', $font_size],
                -anchor => $anchor,
                -tags => [@tags, 'contig_label', $group],
                );

            my @bkgd = $canvas->bbox($group);

            my $sp = $font_size / 5;
            expand_bbox(\@bkgd, $sp);
            my $bkgd_rectangle = $canvas->createRectangle(
                @bkgd,
                -outline    => '#cccccc',
                -tags       => [@tags, 'bkgd_rec', $group],
                );
            unless ($text_nudge_flag) {
                my( $small, $big ) = sort {$a <=> $b} map abs($_), @bkgd[1,3];
                $nudge_distance = ($big - $small + 3) * $y_dir;
                $text_nudge_flag = 1;
            }
        }
        
        $band->nudge_into_free_space($group, $nudge_distance);
    }
    $canvas->delete('bkgd_rec');
    
    my @bbox = $band->band_bbox;
    confess "failed to get bounding box for band" unless grep /\d/, @bbox;
    $bbox[0] = 0;
    $bbox[2] = $band->width;
    $canvas->createRectangle(
        @bbox,
        -outline    => undef,
        -fill       => undef,
        -tags       => [@tags],
        );
    
    #confess "No mapcontigs in virtual contig" unless $map_contig_count;
    #print STDERR "Done render tilingpath\n";
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::TilingPath

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

