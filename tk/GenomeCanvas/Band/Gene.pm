
### GenomeCanvas::Band::Gene

package GenomeCanvas::Band::Gene;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub render {
    my( $band ) = @_;
    
    while (my($vc, $x_offset) = $band->next_sub_VirtualContig) {
        $band->draw_gene_features_on_sub_vc($vc, $x_offset);
    }
}

sub draw_titles {
    my( $band ) = @_;
    
    my $canvas      = $band->canvas;
    my $vc          = $band->virtual_contig;
    my $type_color  = $band->gene_type_color_hash;
    my $font_size   = $band->font_size;
    my $y_offset    = $band->y_offset;
    my @tags        = $band->tags;
    
    my $square_side = $font_size * 2;

    # Write "Genes" and move y_offset
    $canvas->createText(
        0 - $square_side, $y_offset + $font_size,
        -text       => $band->title || 'Genes',
        -font       => ['helvetica', $font_size * 1.2],
        -anchor     => 'ne',
        -tags       => [@tags],
        );
    $y_offset += $font_size * 2.2;
    
    # Print key
    my $x2 = 0 - (2 * $font_size);
    my $x1 = $x2 - $square_side;
    my $label_type = $band->label_type_list;
    for (my $i = 0; $i < @$label_type; $i++) {
        my($label, $type) = @{$label_type->[$i]};
        my $y1 = $y_offset + (2.5 * $font_size * $i) + $font_size;
        my $y2 = $y1 + $square_side;
        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill       => $type_color->{$type},
            -outline    => undef,
            -tags       => [@tags],
            );
        
        my $tx = $x1 - $font_size;
        my $ty = $y2 - ($square_side / 2);# - ($font_size / 3);
        $canvas->createText(
            $tx, $ty,
            -text       => $label,
            -font       => ['helvetica', $font_size],
            -anchor     => 'e',
            -tags       => [@tags],
            );
    }
}

sub current_color {
    my( $band, $color ) = @_;
    
    if ($color) {
        confess "Invalid color '$color'"
            unless $color =~ /^#[a-fA-F0-9]{6}$/;
        $band->{'_current_color'} = $color;
    }
    return $band->{'_current_color'} || '#000000';
}

sub label_type_color_list {
    my( $band, @list ) = @_;
    
    my $type_color = {};
    my $label_list = [];
    foreach my $ele (@list) {
        my( $label, $type, $color ) = @$ele;
        $type_color->{$type} = $color;
        push(@$label_list, [$label, $type]);
    }
    $band->gene_type_color_hash($type_color);
    $band->label_type_list($label_list);
}

sub label_type_list {
    my( $band, $list ) = @_;
    
    if ($list) {
        confess "'$list' is not a ARRAY ref"
            unless ref($list) eq 'ARRAY';
        $band->{'_label_type_list'} = $list;
    }
    return $band->{'_label_type_list'};
}

sub gene_type_color_hash {
    my( $band, $color_hash ) = @_;
    
    if ($color_hash) {
        confess "'$color_hash' is not a HASH ref"
            unless ref($color_hash) eq 'HASH';
        $band->{'_gene_type_color_hash'} = $color_hash;
    }
    return $band->{'_gene_type_color_hash'};
}

sub gene_type_color {
    my( $band, $type ) = @_;
    
    my $hash = $band->{'_gene_type_color_hash'}
        or return $band->current_color;
    return $hash->{$type};
}

sub draw_gene_features_on_sub_vc {
    my( $band, $vc, $x_offset ) = @_;

    my $y_dir       = $band->tiling_direction;
    my $rpp         = $band->residues_per_pixel;
    my $y_offset    = $band->y_offset;
    my @tags        = $band->tags;
    my $font_size   = $band->font_size;
    my $canvas      = $band->canvas;
    
    my $rectangle_height = $font_size * 10 / 12;
    my $rectangle_border = $font_size * 1  / 12;
    my $nudge_distance = ($rectangle_height + 1) * $y_dir;

    my $text_nudge_flag = 0;
    foreach my $vg ($vc->get_all_VirtualGenes) {        
        my $color = $band->gene_type_color($vg->gene->type)
            or next;
        $band->current_color($color);
        my $start = $x_offset + $vg->start;
        my $end   = $x_offset + $vg->end;
        my $id    = $vg->id;
        #warn "[$x_offset] $id: $start -> $end\n";
        
        my $group = "gene_group-$id-$vc";
        
        my $x1 = $start / $rpp;
        my $x2 = $end   / $rpp;
        $canvas->createRectangle(
            $x1, $y_offset, $x2, $y_offset + $rectangle_height,
            -fill => $color,
            -outline => undef,
            -tags => [@tags, 'gene_rectangle', $group],
            );

        my $label_space = $rectangle_height * (3 / 4);
        my( $anchor, $y1 );
        if ($y_dir == 1) {
            $anchor = 'nw';
            $y1 = $y_offset + $rectangle_height + $label_space;
        } else {
            $anchor = 'sw';
            $y1 = $y_offset + (-1 * $label_space);
        }
        
        if ($vg->strand == 1) {
            $band->forward_arrow($x2, $rectangle_height, @tags, $group);
        } else {
            $band->reverse_arrow($x1, $rectangle_height, @tags, $group);
        }

        if ($band->show_labels) {
            
            my $label = $canvas->createText(
                $x1, $y1,
                -text => $id,
                -font => ['helvetica', $font_size],
                -anchor => $anchor,
                -tags => [@tags, 'gene_label', $group],
                );

            my @bkgd = $canvas->bbox($group);

            my $sp = $font_size / 5;
            $band->expand_bbox(\@bkgd, $sp);
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
}

sub forward_arrow {
    my( $band, $x1, $size, @tags ) = @_;
    
    my $y_offset = $band->y_offset;
    my $canvas   = $band->canvas;
    
    my $x_dist = $size * (2 / 3);
    my $y1 = $y_offset + ($size / 2);
    my @coords = (
        $x1,            $y1,
        $x1 - $x_dist,  $y1 + $size,
        $x1 + $x_dist,  $y1,
        $x1 - $x_dist,  $y1 - $size,
        );
    
    return $canvas->createPolygon(
        @coords,
        -fill   => $band->current_color,
        -tags   => ['gene_arrow', @tags],
        );
}

sub reverse_arrow {
    my( $band, $x1, $size, @tags ) = @_;
    
    my $y_offset = $band->y_offset;
    my $canvas   = $band->canvas;
    
    my $x_dist = $size * (2 / 3);
    my $y1 = $y_offset + ($size / 2);
    my @coords = (
        $x1,            $y1,
        $x1 + $x_dist,  $y1 + $size,
        $x1 - $x_dist,  $y1,
        $x1 + $x_dist,  $y1 - $size,
        );
    
    return $canvas->createPolygon(
        @coords,
        -fill   => $band->current_color,
        -tags   => ['gene_arrow', @tags],
        );
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::Gene

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

