
### GenomeCanvas::DensityBand::RepeatFeature

package GenomeCanvas::Band::HomolFeature;

use strict;
use Carp;
use GenomeCanvas::Band::MultiBand;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band::MultiBand');

sub render {
    my( $band ) = @_;
    
    $band->draw_homol_features;
    # $band->draw_sequence_gaps;
    $band->draw_outline_and_labels;
}

sub homol_classes {
    my( $band, @classes ) = @_;
    
    if (@classes) {
        $band->{'_homol_classes'} = [@classes];
    }
    if (my $c = $band->{'_homol_classes'}) {
        @classes = @$c;
    } else {
        @classes = ( { name => "Mouse", gff_key => "MouseBlastzTight", colour => "#a0522d"}, 
		     { name => "Rat", gff_key => "RatBlastzTight", colour => "#a0522d"}, 
		     { name => "Fugu", gff_key => "FuguEcore", colour => "#2e8b57"}, 
		     { name => "Tetraodon", gff_key => "TetraodonEcore", colour => "#2e8b57"}, 
		     { name => "Zebrafish", gff_key => "ZebrafishEcore", colour => "#2e8b57"} );
    }

    return @classes;
}


sub draw_homol_features {
    my( $band ) = @_;

    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";

    my $feats = $band->get_features;

    my @class_list = $band->homol_classes;
    $band->strip_labels(map { $_->{'name'} } @class_list);
    $band->strip_colours(map { $_->{'colour'} } @class_list);

    my $height    = $band->height;
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    my $color     = $band->band_color;
    my @tags      = $band->tags;

#    $canvas->createRectangle(
#         0, $y_offset, $band->width, $y_offset + $height,
#	 -fill       => undef,
#	 -outline    => undef,
#         -tags       => [@tags],
#        );

    for(my $x = 0; $x < @class_list; $x++) {
	$band->draw_multi_segment( $x, @{$feats->{$class_list[$x]->{'gff_key'}}} );
    }

}

sub get_features {
    my $band = shift;

    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $file = $band->feature_file
        or confess "feature_file not set";
    my $global_offset = $vc->_global_start - 1;

    my @ind = $band->type_start_end_column_indices;

    open F, $file or confess "Can't open '$file' : $!";

    my %features;
    while(<F>) {
	my ($type, $start, $end) =  (split /\s+/, $_)[@ind];
	$start -= $global_offset;
	$end -= $global_offset;

	next if $start < 1;
        next if $end > $vc->length;
	
	push @{$features{$type}}, {start => $start, end => $end};
    }

    return \%features;
}




sub feature_file {
    my( $self, $file ) = @_;
    
    if ($file) {
        $self->{'_feature_file'} = $file;
    }
    return $self->{'_feature_file'};
}



sub type_start_end_column_indices {
    my( $self, @indices ) = @_;
    
    if (@indices) {
        unless (@indices == 3) {
            confess "Need 3 indices, for type, start and end columns, but got ", scalar(@indices);
        }
        $self->{'_type_start_end_column_indices'} = [@indices];
    }
    my $ind_ref = $self->{'_type_start_end_column_indices'};
    if ($ind_ref) {
        return @$ind_ref;
    } else {
        return (2,4,5);   # Type + Start + End in GFF
    }
}


1;

__END__

