
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
    my( $band ) = @_;
    
    my $y_offset = ($band->frame)[3];
    
    my $vc = $band->virtual_contig;
    my $canvas = $band->canvas;
    my $scale = $band->residues_per_pixel;
    foreach my $map_c ($vc->_vmap->each_MapContig) {
    
        my $start  = $map_c->start;
        my $end    = $map_c->end;
        my $raw_start = $map_c->rawcontig_start;
        my $raw_end   = $map_c->rawcontig_end;
        my $contig = $map_c->contig;
        my $length = $contig->length;
        my $name = $contig->id;
        printf STDERR "%-10s  %2d %6d %6d %6d  %10d %10d\n", $name, $map_c->orientation, $raw_start, $raw_end, $length, $start, $end;

        my( $left_overhang, $right_overhang );
        if ($map_c->orientation == 1) {
            $left_overhang  = $raw_start - 1;
            $right_overhang = $length - $raw_end;
        } else {
            $left_overhang  = $length - $raw_end;
            $right_overhang = $raw_start - 1;
        }

        my $x1 = ($start - $left_overhang + 1) / $scale;
        my $x2 = ($end   + $right_overhang)    / $scale;
        
        my $rectangle_height = 8;
        my $rec = $canvas->createRectangle(
            $x1, 0, $x2, $rectangle_height,
            -fill => 'black',
            -outline => undef,
            -tags => ['contig', $name],
            );
        
        if ($band->gold) {
            
            
            # Render golden path segment in gold
            my $gold = $canvas->createRectangle(
                ($start / $scale), 1,
                ($end / $scale), $rectangle_height - 1,
                -fill => 'gold',
                -outline => undef,
                -tags => ['contig_gold', $name],
                );
        }

        my $nudge_distance = $rectangle_height;
        if ($band->show_labels) {
            my $label = $canvas->createText(
                $x1, -1,
                -text => $name,
                -font => ['helvetica', 12],
                -anchor => 'sw',
                -tags => ['contig_label', $name],
                );

            my @bbox = $canvas->bbox($name);

            my $sp = 3;
            $band->expand_bbox(\@bbox, $sp);
            my $bkgd = $canvas->createRectangle(
                @bbox,
                -fill    => undef,
                -outline => undef,
                -tags => ['contig_bkgd', $name],
                );
            $canvas->lower($bkgd, $rec);
            $nudge_distance = -10;
        }
        
        $band->nudge_into_free_space($name, $nudge_distance);
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::TilingPath

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

