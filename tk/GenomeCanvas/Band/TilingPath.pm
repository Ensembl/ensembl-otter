
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

sub direction {
    my( $band, $dir ) = @_;
    
    if ($dir) {
        confess "direction must be '1' or '-1'"
            unless $dir == 1 or $dir == -1;
        $band->{'_tiling_direction'} = $dir;
    }
    return $band->{'_tiling_direction'} || -1;
}

sub virtual_contig {
    my( $band, $vc ) = @_;
    
    if ($vc) {
        confess "Not a Bio::EnsEMBL::Virtual::Contig : '$vc'"
            unless ref($vc) and $vc->isa('Bio::EnsEMBL::Virtual::Contig');
        $band->{'_virtual_contig'} = $vc;
    }
    return $band->{'_virtual_contig'};
}

sub gold {
    my( $band, $flag ) = @_;
    
    if (defined $flag) {
        $band->{'_show_gold'} = $flag;
    }
    return $band->{'_show_gold'};
}

sub show_labels {
    my( $band, $flag ) = @_;
    
    if (defined $flag) {
        $band->{'_show_labels'} = $flag;
    }
    return $band->{'_show_labels'};
}

sub render {
    my( $band, $y_offset, @tags ) = @_;
    
    my $canvas = $band->canvas;
    my $vc     = $band->virtual_contig;
    my $y_dir  = $band->direction;
    my $rpp    = $band->residues_per_pixel;

    if ($y_dir == -1) {
        # We have to build above the other bands
        $y_offset = ($canvas->bbox('all'))[1] - 100;
    }

    foreach my $map_c ($vc->_vmap->each_MapContig) {
    
        my $start  = $map_c->start;
        my $end    = $map_c->end;
        my $raw_start = $map_c->rawcontig_start;
        my $raw_end   = $map_c->rawcontig_end;
        my $contig = $map_c->contig;
        my $length = $contig->length;
        my $name = $contig->id;
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
        
        my $rectangle_height = 8;
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
                ($start / $rpp), $rectangle[1] + 1,
                ($end / $rpp),   $rectangle[3] - 1,
                -fill => 'gold',
                -outline => undef,
                -tags => [@tags, 'contig_gold', $group],
                );
        }

        my $nudge_distance = $rectangle_height + 1;
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
                -font => ['helvetica', 12],
                -anchor => $anchor,
                -tags => [@tags, 'contig_label', $group],
                );

            my @bkgd = $canvas->bbox($group);

            my $sp = 3;
            $band->expand_bbox(\@bkgd, $sp);
            $bkgd_rectangle = $canvas->createRectangle(@bkgd);
            $nudge_distance = 10;
        }
        
        $nudge_distance *= $y_dir;
        $band->nudge_into_free_space($group, $nudge_distance);
        $canvas->delete($bkgd_rectangle) if $bkgd_rectangle;
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::TilingPath

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

