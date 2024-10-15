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

sub homol_tracks {
    my( $band, @tracks ) = @_;
    
    if (@tracks) {
        $band->{'_homol_tracks'} = [@tracks];
    }
    if (my $c = $band->{'_homol_tracks'}) {
        @tracks = @$c;
    } else {
        @tracks = ( { name => "Mouse",     color => "#a0522d"}, 
		    { name => "Rat",       color => "#a0522d"}, 
		    { name => "Fugu",      color => "#2e8b57"}, 
		    { name => "Tetraodon", color => "#2e8b57"}, 
		    { name => "Zebrafish", color => "#2e8b57"} );
    }

    return @tracks;
}


sub draw_homol_features {
    my( $band ) = @_;

    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";

    my $feats = $band->get_features;

    my @track_list = $band->homol_tracks;
    $band->strip_labels(map { $_->{'name'} } @track_list);
    $band->strip_colors(map { $_->{'color'} } @track_list);

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

    for(my $x = 0; $x < @track_list; $x++) {
	$band->draw_multi_segment( $x, @{$feats->{$track_list[$x]->{'name'}}} );
    }

}

sub get_features {
    my $band = shift;

    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $file = $band->feature_file
        or confess "feature_file not set";
    my $global_offset = $vc->chr_start - 1;

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

