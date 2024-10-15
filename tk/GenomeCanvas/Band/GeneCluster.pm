=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::Band::GeneCluster

package GenomeCanvas::Band::GeneCluster;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');



sub span_file {
    my( $self, $span_file ) = @_;
    
    if ($span_file) {
        $self->{'_span_file'} = $span_file;
    }
    return $self->{'_span_file'};
}


sub cluster_file {
    my( $self, $cluster_file ) = @_;
    
    if ($cluster_file) {
        $self->{'_cluster_file'} = $cluster_file;
    }
    return $self->{'_cluster_file'};
}


sub get_gene_cluster_data {
    my ($band, $vc, $spans) = @_;

    my (@clusters, %gene_positions);

    foreach my $sp (@$spans) {
	if (defined $sp->[0]) {
	    $gene_positions{lc($sp->[0])} = { start => $sp->[2], end => $sp->[3]};
	}
    }
    my $file = $band->cluster_file;

    my $ignored_clusters = 0;

    open(CLUST, $band->cluster_file) or die "Could not open Cluster file $file\n";
    while(<CLUST>) {
	/^\"(.+)\"\s+(.+)$/ and do {
	    my ($clust_name, $rest) = ($1, $2);

	    my ($clust_st, $clust_en, @members);

	    my @genes = split(/\s+/, $rest);
	    foreach my $g (@genes) {
		if (exists($gene_positions{lc($g)})) {
		    my $pos = $gene_positions{lc($g)};
		    
		    $clust_st = $pos->{'start'} if not defined $clust_st or 
			$pos->{'start'} < $clust_st;

		     $clust_en = $pos->{'end'} if not defined $clust_en or 
			$pos->{'end'} > $clust_en;

		    push @members, {name => $g, position => $pos };
		}
	    }

	    if (scalar(@genes) == scalar(@members)) {
		my $cluster = { start => $clust_st,
				end => $clust_en,
				name => $clust_name,
				members => [sort {$a->{'position'}->{'start'} <=> $b->{'position'}->{'start'}} @members] };
		
		push @clusters, $cluster;
	    }
	    else {
		$ignored_clusters++;
	    }
	}
    }

    if ($ignored_clusters != 0) {
	print STDERR "GeneCluster: ignored $ignored_clusters clusters (at least one gene could not be positioned)\n"; 
    }

    return (sort {$a->{'start'} <=> $b->{'start'}} @clusters);
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
					  $s[6] eq "+" ? 1 : -1);
	    next if $st < 1;
	    next if $en > $vc->length;
	    
	    my ($id, $desc);
	    if ($s[8] =~ /ID\=\"([^\"]+)\"/) {
		$id = $1;
	    }

	    push(@span, [$id, $type, $st, $en, $str]) if defined $id;
        }
        close SPANS;
    }
    else {
        foreach my $vg (@{$vc->get_all_Genes}) {
            push(@span, [$vg->stable_id, $vg->type, $vg->start, $vg->end, $vg->strand]);
        }
    }
    return @span;
}


sub render {
    my( $band ) = @_;

    my $vc = $band->virtual_contig;
    my $x_offset = 0;

    my $y_dir       = $band->tiling_direction;
    my $rpp         = $band->residues_per_pixel;
    my $y_offset    = $band->y_offset;
    my @tags        = $band->tags;
    my $canvas      = $band->canvas;
    my $font_size   = $band->font_size;

    my $circle_height = $font_size;
    my $circle_width = $font_size / 2;
    my $nudge_distance = $y_dir * 4;

    my @spans = $band->get_gene_span_data($vc);
    my @clusters = $band->get_gene_cluster_data($vc, \@spans );

    my $text_nudge_flag = 0;


    $canvas->createRectangle(
        0, $y_offset, $band->width, $y_offset + $circle_height,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );

    for (my $i = 0; $i < @clusters; $i++) {
	my $clust = $clusters[$i];
	
	my $id     = $clust->{'name'};
	my $start  = $x_offset + $clust->{'start'};
	my $end    = $x_offset + $clust->{'end'};
	my $group = "gene_cluster_group-$i-$vc";
	
	my $x1 = $start / $rpp;
	my $x2 = $end / $rpp;

	my $y1 = $y_offset + ($circle_height / 2);
	my $y2 = $y1;

	$canvas->createLine($x1, $y1, $x2, $y2,
			    -fill       => "black",
			    -tags       => [@tags, 'gene_cluster', $group],
			    );

	foreach my $member (@{$clust->{'members'}}) {
	    my $this_x1 = ($member->{'position'}->{'start'} + 
			   $member->{'position'}->{'end'}) / (2 * $rpp) 
			   - ($circle_width / 2);
	    my $this_y1 = $y_offset;

	    my $this_x2 = $this_x1 + $circle_width;
	    my $this_y2 = $this_y1 + $circle_height;

	    $canvas->createOval( $this_x1, $this_y1, $this_x2, $this_y2,
				   -fill => "yellow",
				   -tags => [@tags, 'gene_cluster_members', $group] );
	}

	    
	$x1 = ($x1 + $x2) / 2;
	$y1 = $y_offset + $circle_height + 2;

	my $label = $canvas->createText($x1, $y1,
					-text => $id,
					-font => ['helvetica', $font_size],
					-anchor => "n",
					-tags => [@tags, 'gene_cluster_label', $group],
					);
	
	my @bkgd = $canvas->bbox($group);
	
	my $sp = $circle_height / 4;
	$bkgd[0] -= $sp;
	$bkgd[2] += $sp;
	my $bkgd_rectangle = $canvas->createRectangle(@bkgd,
						      -outline    => '#cccccc',
						      -tags       => [@tags, 'bkgd_rec', $group],
						      );
	
	#unless ($text_nudge_flag) {
	#my( $small, $big ) = sort {$a <=> $b} map abs($_), @bkgd[1,3];
	#$nudge_distance = ($big - $small + 3) * $y_dir;
	#   $nudge_distance *= 2;
	#   $text_nudge_flag = 1;
	#}
	
	$band->nudge_into_free_space($group, $nudge_distance);
    }
    
    $canvas->delete('bkgd_rec');
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::Gene

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

