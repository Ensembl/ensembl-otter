
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
        my $get_types = $band->virtual_contig->dbobj->prepare(q{
            SELECT DISTINCT type
            FROM genetype
            });
        $get_types->execute;
        my( @gene_types );
        while (my ($t) = $get_types->fetchrow) {
            push(@gene_types, $t);
        }
        $band->{'_strip_labels'} = [sort @gene_types];
        return @gene_types;
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
    foreach my $vg ($vc->get_all_VirtualGenes) {
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

