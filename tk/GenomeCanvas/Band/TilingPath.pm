
### GenomeCanvas::Band::TilingPath

package GenomeCanvas::Band::TilingPath;

use strict;
use Carp;
use GenomeCanvas::Band;

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

sub tiling_direction {
    my( $band, $dir ) = @_;
    
    if ($dir) {
        confess "direction must be '1' or '-1'"
            unless $dir == 1 or $dir == -1;
        $band->{'_tiling_direction'} = $dir;
    }
    return $band->{'_tiling_direction'} || -1;
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

sub show_labels {
    my( $band, $flag ) = @_;
    
    if (defined $flag) {
        $band->{'_show_labels'} = $flag;
    }
    return $band->{'_show_labels'};
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
    my $name_morpher = $band->name_morpher;

    if ($y_dir == -1) {
        # We have to build above the other bands
        my $y_top = ($canvas->bbox('all'))[1] || 0;
        $y_offset = $y_top - 100;
    }

    my $map_contig_count = 0;
    my $rectangle_height = $band->font_size * 10 / 12;
    my $rectangle_border = $band->font_size * 1 / 12;
    my $nudge_distance = ($rectangle_height + 1) * $y_dir;
    my $text_nudge_flag = 0;
    foreach my $map_c ($vc->_vmap->each_MapContig) {
        $map_contig_count++;
        my $start  = $map_c->start;
        my $end    = $map_c->end;
        my $raw_start = $map_c->rawcontig_start;
        my $raw_end   = $map_c->rawcontig_end;
        my $contig = $map_c->contig;
        my $length = $contig->length;
        my $name = $contig->id;
        if ($name_morpher) {
            $name = &$name_morpher($name);
        }
        my $group = "$tags[0]::$name";
        #printf STDERR "%-10s  %2d %6d %6d %6d  %10d %10d\n", $name, $map_c->orientation, $raw_start, $raw_end, $length, $start, $end;

        my( $left_overhang, $right_overhang );
        if ($map_c->orientation == 1) {
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

        my( $bkgd_rectangle );
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
            $band->expand_bbox(\@bkgd, $sp);
            $bkgd_rectangle = $canvas->createRectangle(
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
    confess "No mapcontigs in virtual contig" unless $map_contig_count;
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::TilingPath

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

