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


### GenomeCanvas::DensityBand::Gene

package GenomeCanvas::DensityBand::Gene;

use strict;

use Carp;
use GenomeCanvas::DensityBand;

use vars '@ISA';
@ISA = ('GenomeCanvas::DensityBand');


sub render {
    my( $band ) = @_;
    
    #print STDERR "Drawing gene features... ";
    $band->draw_gene_features;
    #print STDERR "done\nDrawing sequence gaps... ";
    $band->draw_sequence_gaps;
    #print STDERR "done\nDrawing labels... ";
    $band->draw_outline_and_labels;
    #print STDERR "done\n";
}

sub strip_labels {
    my( $band, @labels ) = @_;
    
    if (@labels) {
        $band->{'_strip_labels'} = [@labels];
    }
    if (my $l = $band->{'_strip_labels'}) {
        return @$l;
    } else {
	my %type_hash;
	foreach my $g (@{$band->virtual_contig->get_all_Genes}) {
	    $type_hash{$g->type} = 1;
	}

        $band->{'_strip_labels'} = [sort keys %type_hash];
        return @{$band->{'_strip_labels'}};
    }
}

sub draw_gene_features {
    my( $band ) = @_;
    
    while (my($vc, $x_offset) = $band->next_sub_VirtualContig) {
        $band->draw_gene_features_on_sub_vc($vc, $x_offset);
    }    
}

sub draw_gene_features_on_sub_vc {
    my( $band, $vc, $x_offset ) = @_;

    my @types = $band->strip_labels;

    my %gene_types = map {$_, []} @types;
    foreach my $vg (@{$vc->get_all_Genes}) {
        my $type = $vg->gene->type;
        if (my $strip = $gene_types{$type}) {
            push(@$strip, $vg);
        }
    }
    my $vc_length = $vc->length;
    for (my $i = 0; $i < @types; $i++) {
        my $type = $types[$i];
        $band->draw_density_segment($x_offset, $i, $vc_length, @{$gene_types{$type}});
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::DensityBand::Gene

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

