
### GenomeCanvas::Band::Gene

package GenomeCanvas::Band::Gene;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub render {
    my( $band ) = @_;
    
    #while (my($vc, $x_offset) = $band->next_sub_VirtualContig) {
    #    $band->draw_gene_features_on_sub_vc($vc, $x_offset);
    #}
    $band->draw_gene_features_on_sub_vc($band->virtual_contig, 0);
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
    my $canvas      = $band->canvas;
    my $font_size   = $band->font_size;

    my $rectangle_height = $font_size;
    my $nudge_distance = $rectangle_height * $y_dir;

    my @genes = $vc->get_all_VirtualGenes;
    my( @ranked_genes );
    if (my $label_type = $band->label_type_list) {
        my @types = map $_->[1], @$label_type;
        my( %type_level );
        for (my $i = 0; $i < @types; $i++) {
            $type_level{$types[$i]} = $i;
        }
        foreach my $vg (@genes) {
            my $type = $vg->gene->type;
            my $i = $type_level{$type};
            next unless defined($i);
            $ranked_genes[$i] ||= [];
            push(@{$ranked_genes[$i]}, $vg);
        }
    } else {
        @ranked_genes = [@genes];
    }
    
    my $text_nudge_flag = 0;
    foreach my $rank (grep $_, @ranked_genes) {
        foreach my $vg (sort {$a->start <=> $b->start} @$rank) {
            my $color = $band->gene_type_color($vg->gene->type)
                or next;
        
            my $id    = $vg->id;
            my $group = "gene_group-$id-$vc";
        
            $band->current_color($color);
            my $start = $x_offset + $vg->start;
            my $end   = $x_offset + $vg->end;
            #warn "[$x_offset] $id: $start -> $end\n";


            my $x1 = $start / $rpp;
            my $x2 = $end   / $rpp;

            $band->draw_gene_arrow($x1, $x2, $vg->strand, $rectangle_height, @tags, $group);

            if ($band->show_labels) {

                my $label_space = $rectangle_height / 4;
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
                    -text => $id,
                    -font => ['helvetica', $font_size],
                    -anchor => $anchor,
                    -tags => [@tags, 'gene_label', $group],
                    );

                my @bkgd = $canvas->bbox($group);

                my $sp = $font_size / 4;
                $bkgd[0] -= $sp;
                $bkgd[2] += $sp;
                my $bkgd_rectangle = $canvas->createRectangle(
                    @bkgd,
                    -outline    => '#cccccc',
                    -tags       => [@tags, 'bkgd_rec', $group],
                    );

                unless ($text_nudge_flag) {
                    #my( $small, $big ) = sort {$a <=> $b} map abs($_), @bkgd[1,3];
                    #$nudge_distance = ($big - $small + 3) * $y_dir;
                    $nudge_distance *= 2;
                    $text_nudge_flag = 1;
                }
            }

            $band->nudge_into_free_space($group, $nudge_distance);
        }
    }

    $canvas->delete('bkgd_rec');
}

sub draw_gene_arrow {
    my( $band, $x1, $x2, $strand, $rectangle_height, @tags ) = @_;

    my $y_offset = $band->y_offset;
    
    my $u = $rectangle_height / 8;
    my $length = $x2 - $x1;
    my $head_center = 2 * $u;

    # I draw a reverse strand gene, and then flip
    # the x coordinates if it is a forward strand gene.
    # This is beacause I only have to adjust 3 coordinates
    # by the gene length to get the arrow for a reverse
    # strand gene.

    # These coordinates are the same, whether or
    # not the gene is longer than the arrowhead.
    my @arrow_head_start = map $u * $_, (
        -2,  0,
         3,  5,
         5,  5,
        );
    my @arrow_head_end = map $u * $_, (
         5, -5,
         3, -5,
        );
    
    my( @coords );
    if ($length < $head_center) {
        # Gene is within arrowhead
        @coords = (
            @arrow_head_start,
            $head_center,    0,
            @arrow_head_end,
            );
    } else {
        # Gene is longer then arrowhead
        my $tail_x_start = $u * 1.8;
        @coords = (
            @arrow_head_start,
            $tail_x_start + $head_center,     3 * $u,
            $tail_x_start + $length,          3 * $u,
                          + $length,          0,
            $tail_x_start + $length,         -3 * $u,
            $tail_x_start + $head_center,    -3 * $u,
            @arrow_head_end,
            );
    }

    # Flip coordinates for forward strand gene
    if ($strand == 1) {
        for (my $i = 0; $i < @coords; $i += 2) {
            my $x = $coords[$i];
            $coords[$i] = (-1 * $x) + $length;
        }
    }

    # Adjust x and y coordinates to put the gene
    # in the correct place.
    for (my $i = 0; $i < @coords; $i += 2) {
        $coords[$i]   += $x1;
        $coords[$i+1] += $y_offset;
    }
    
    return $band->canvas->createPolygon(
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

