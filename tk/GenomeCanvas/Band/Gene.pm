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


### GenomeCanvas::Band::Gene

package GenomeCanvas::Band::Gene;

use strict;
use Carp;
use GenomeCanvas::Band;
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'biotype_status2method';

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub render {
    my( $band ) = @_;
    
    $band->draw_gene_features_on_vc($band->virtual_contig, 0);
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

    my $xright = ($band->band_bbox)[2] + 2 * $font_size;
    if (($vc->length / $band->residues_per_pixel) + $square_side > $xright) {
	$xright = ($vc->length / $band->residues_per_pixel) + $square_side;
    }
    $canvas->createText(
        $xright, $y_offset + $font_size,
        -text       => $band->title || 'Genes',
        -font       => ['helvetica', $font_size * 1.2],
        -anchor     => 'nw',
        -tags       => [@tags],
        );

    $y_offset += $font_size * 2.2;
    
    if ($band->show_key) {
	    # Print key

	    # left
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

	    # right
	    $x1 = $xright;
	    $x2 = $x1 + $square_side;

	    $label_type = $band->label_type_list;
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

	        my $tx = $x2 + $font_size;
	        my $ty = $y2 - ($square_side / 2);# - ($font_size / 3);
	        $canvas->createText(
				    $tx, $ty,
				    -text       => $label,
				    -font       => ['helvetica', $font_size],
				    -anchor     => 'w',
				    -tags       => [@tags],
				    );
	    }
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

sub gene_arrow_width {
    my ($band, $width ) = @_;

    if ($width) {
	$band->{'_gene_arrow_width'} = $width;

    }
    return $band->{'_gene_arrow_width'} || $band->font_size;
}

sub gene_type_color {
    my( $band, $type ) = @_;
    
    my $hash = $band->{'_gene_type_color_hash'}
        or return $band->current_color;
    return $hash->{$type};
}


sub span_file {
    my( $self, $span_file ) = @_;
    
    if ($span_file) {
        $self->{'_span_file'} = $span_file;
    }
    return $self->{'_span_file'};
}


sub get_gene_span_data {
    my( $self, $vc ) = @_;
    
    my( @span );
    if (my $span_file = $self->span_file) {

	    my $global_offset = $vc->chr_start - 1;

        open SPANS, $span_file or die "Can't read '$span_file' : $!";
	    # assume GFF
        while (<SPANS>) {
	        /^\#/ and next;
                my @s = split /\t/, $_;

	        my ($type, $st, $en, $str) = ($s[1], 
					      $s[3] - $global_offset, 
					      $s[4] - $global_offset, 
					      $s[6] eq "+" ? 1 : ($s[6] eq "-" ? -1 : undef));
	        next if $st < 1;
	        next if $en > $vc->length;

	        my ($id, $desc);
	        if ($s[8] =~ /(Sequence |ID=")([^"]+)/) {
		        $id = $2;
	        }

	        push(@span, [$id, $type, $st, $en, $str]) if defined $id;
        }
        close SPANS;
    }
    else {
        foreach my $gene (@{$vc->get_all_Genes}) {
            next unless $gene->source eq 'havana';
            my $id = $gene->isa('Bio::Vega::Gene')
                ? $gene->get_all_Attributes('name')->[0]->value
                : $gene->stable_id;
            #my $desc = $gene->description || 'NO DESCRIPTION';
            #print STDERR "$id: $desc\n";
            my $type = $gene->biotype =~ /pseudo/i
                ? 'Pseudogene'
                : biotype_status2method($gene->biotype, $gene->status);
            if ($type eq 'Polymorphic') {
                $type = 'Known_CDS';
                warn "Changed type of gene '$id' from Polymorphic to $type";
            }
            #warn join("\t", $id, $type, $gene->start, $gene->end, $gene->strand), "\n";
	        push(@span, [$id, $type, $gene->start, $gene->end, $gene->strand]);
        }
    }
    return @span;
}

sub ignore_label_sub {
    my( $self, $ignore_label_sub ) = @_;
    
    if ($ignore_label_sub) {
        $self->{'_ignore_label_sub'} = $ignore_label_sub;
    }
    return $self->{'_ignore_label_sub'};
}

sub show_key {
    my( $self, $show_key ) = @_;
    
    if ($show_key) {
        $self->{'_show_key'} = $show_key;
    }
    return $self->{'_show_key'};
}

sub draw_gene_features_on_vc {
    my( $band, $vc, $x_offset ) = @_;

    my $y_dir       = $band->tiling_direction;
    my $rpp         = $band->residues_per_pixel;
    my $y_offset    = $band->y_offset;
    my @tags        = $band->tags;
    my $canvas      = $band->canvas;
    my $font_size   = $band->font_size;

    my $rectangle_height = $band->gene_arrow_width;
    my $nudge_distance = $rectangle_height * $y_dir;

    my @spans = $band->get_gene_span_data($vc);

    my( @ranked_genes );
    if (my $label_type = $band->label_type_list) {
        my @types = map $_->[1], @$label_type;
        my( %type_level );
        for (my $i = 0; $i < @types; $i++) {
            $type_level{$types[$i]} = $i;
        }
        foreach my $sp (@spans) {
            my $type = $sp->[1];
            my $i = $type_level{$type};
            unless (defined($i)) {
                warn "Ignoring '$type' gene\n";
                next;
            }
            $ranked_genes[$i] ||= [];
            push(@{$ranked_genes[$i]}, $sp);
        }
    } else {
        # @ranked_genes = [@genes];
	    @ranked_genes = [@spans];
    }
    
    my $ignore_label_sub = $band->ignore_label_sub;
    
    my $text_nudge_flag = 0;
    for (my $i = 0; $i < @ranked_genes; $i++) {
        my $rank = $ranked_genes[$i] or next;

        # Span:
        # 0    1    2     3   4
        # name type start end srand
        foreach my $sp (sort {$a->[2] <=> $b->[2]} @$rank) {
            my $color = $band->gene_type_color($sp->[1])
                or next;
            $band->current_color($color);

            my $id     =             $sp->[0];
            my $start  = $x_offset + $sp->[2];
            my $end    = $x_offset + $sp->[3];
            my $strand =             $sp->[4];
	        my $type = $sp->[1];
            my $group = "gene_group-$type-$id-$start-$vc";
            #warn "[$x_offset] $id: $start -> $end\n";

            my $x1 = $start / $rpp;
            my $x2 = $end   / $rpp;

	        if (defined($strand) and ($strand == -1 or $strand == 1)) {
		        $band->draw_gene_arrow($x1, $x2, $strand, $rectangle_height, @tags, $group);
	        }
	        else {
		        $band->draw_gene_rectangle($x1, $x2, $rectangle_height, @tags, $group);
	        }

            if ($i <= 3 and $band->show_labels) {
                warn "Hack to only show labels for certain classes of gene";
            #if ($band->show_labels) {
                
                my( $anchor, $y1 );
                if ($y_dir == 1) {
                    $anchor = 'nw';
                    $y1 = $y_offset + $rectangle_height;
                } else {
                    $anchor = 'sw';
                    $y1 = $y_offset - $rectangle_height;
                }

                unless ($ignore_label_sub and $ignore_label_sub->($id)) {
                    my $label = $canvas->createText(
                        $x1, $y1,
                        -text => $id,
                        -font => ['helvetica', $font_size],
                        -anchor => $anchor,
                        -tags => [@tags, 'gene_label', $group],
                        );
                }

                my @bkgd = $canvas->bbox($group);

                my $sp = $rectangle_height / 4;
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
    
    #my $u = sprintf("%.0f", $rectangle_height / 8);
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


sub draw_gene_rectangle {
    my( $band, $x1, $x2, $rectangle_height, @tags ) = @_;
    
    my $length = $x2 - $x1;
    if ($length < 6) {
        $x2 = $x1 + 6;
    }
    
    my $y_offset = $band->y_offset;
    
    return $band->canvas->createRectangle($x1, $y_offset,
                                          $x2, $y_offset + $rectangle_height,
                                          -outline => $band->current_color,
                                          -fill   => $band->current_color,
                                          -tags   => ['gene_rectangle', @tags],
					  );    
}



1;

__END__

=head1 NAME - GenomeCanvas::Band::Gene

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

