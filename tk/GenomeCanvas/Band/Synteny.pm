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


### GenomeCanvas::DensityBand::Synteny

package GenomeCanvas::Band::Synteny;

use strict;
use Carp;
use GenomeCanvas::Band::MultiBand;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band::MultiBand');

sub render {
    my( $band ) = @_;
    
    $band->draw_synteny_features;
    # $band->draw_sequence_gaps;
    $band->draw_outline_and_labels;
}

sub synteny_tracks {
    my( $band, @tracks ) = @_;
    
    if (@tracks) {
        $band->{'_synteny_tracks'} = [@tracks];
    }
    if (my $c = $band->{'_synteny_tracks'}) {
        @tracks = @$c;
    } else {
        @tracks = ( { name => "Mouse", 
		      color => "#a0522d",
		      class_colors => {  
			  1 => "#7fffd4",   2 => "#7fff00",  3 => "#6495ed",  4 => "#ff7f50",
			  5 => "#ffd700",   6 => "#daa520",  7 => "#bebebe",  8 => "#00ff00",
			  9 => "#ff69b4",  10 => "#add8e6", 11 => "#90ee90", 12 => "#ffc0cb",
			  13 => "#f4a460", 14 => "#00ff7f", 15 => "#d2b48c", 16 => "#ffff00",
			  17 => "#7fffd4", 18 => "#7fff00", 19 => "#6495ed", X => "#ff7f50",			  
		      },
		    }, 
		    { name => "Rat",   
		      color => "#a0522d",
		      class_colors => {  
			  1 => "#7fffd4",  2 => "#7fff00",  3 => "#6495ed",  4 => "#ff7f50",
			  5 => "#ffd700",  6 => "#daa520",  7 => "#bebebe",  8 => "#00ff00",
			  9 => "#ff69b4",  10 => "#add8e6", 11 => "#90ee90", 12 => "#ffc0cb",
			  13 => "#f4a460", 14 => "#00ff7f", 15 => "#d2b48c", 16 => "#ffff00",
			  17 => "#7fffd4", 18 => "#7fff00", 19 => "#6495ed", 20 => "#40e0d0",
			  X => "#ff7f50", Un => "#32cd32",			  
			  "1.random"  => "#7fffd4", "2.random"  => "#7fff00", "3.random"  => "#6495ed",
			  "4.random"  => "#ff7f50", "5.random"  => "#ffd700", "6.random"  => "#daa520",
			  "7.random"  => "#bebebe", "8.random"  => "#00ff00", "9.random"  => "#ff69b4",
			  "10.random" => "#add8e6", "12.random" => "#ffc0cb", "13.random" => "#f4a460",
			  "14.random" => "#00ff7f", "15.random" => "#d2b48c", "16.random" => "#ffff00",
			  "17.random" => "#7fffd4", "18.random" => "#7fff00", "19.random" => "#6495ed",
			  "20.random" => "#40e0d0", "X.random"  => "#ff7f50", "Un.random" => "#32cd32"
			  

			  }});
    }

    return @tracks;
}



sub draw_synteny_features {
    my( $band ) = @_;

    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";

    my $feats = $band->get_features;

    my @track_list = $band->synteny_tracks;
    $band->strip_labels(map { $_->{'name'} } @track_list);
    $band->strip_colors(map { $_->{'color'} } @track_list);

    my $height    = $band->height;
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    my $color     = $band->band_color;
    my @tags      = $band->tags;

    foreach my $tr (@track_list) {
	if (exists($feats->{$tr->{'name'}})) {
	    # add specific colors to the features
	    foreach my $feat (@{$feats->{$tr->{'name'}}}) {
		my ($chr) = $feat->{'label'} =~ /^(\S+):/;

		if (exists($tr->{'class_colors'}) and 
		    exists($tr->{'class_colors'}->{$chr})) {
		    $feat->{'color'} = $tr->{'class_colors'}->{$chr};
		}
	    }
	}

    }

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

    open F, $file or confess "Can't open '$file' : $!";

    my %features;
    while(<F>) {
	my @items = split /\t/, $_;
	my ($org, $start, $end) = @items[1,3,4];

	$start -= $global_offset;
	$end -= $global_offset;

	next if $start < 1;
        next if $end > $vc->length;

	my ($label) = $items[8] =~ /label=\"(\S+)\"/;
	
	push @{$features{$org}}, {start => $start, 
				  end => $end, 
				  label => $label};
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


sub strip_height {
    my( $band ) = @_;
    
    return $band->font_size;
}


1;

__END__

