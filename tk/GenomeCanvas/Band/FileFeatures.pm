=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::Band::FileFeatures

package GenomeCanvas::Band::FileFeatures;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');

sub feature_file {
    my( $self, $file ) = @_;
    
    if ($file) {
        $self->{'_feature_file'} = $file;
    }
    return $self->{'_feature_file'};
}

sub start_end_column_indices {
    my( $self, @indices ) = @_;
    
    if (@indices) {
        unless (@indices == 2) {
            confess "Need 2 indices, for start and end columns, but got ", scalar(@indices);
        }
        $self->{'_start_end_column_indices'} = [@indices];
    }
    my $ind_ref = $self->{'_start_end_column_indices'};
    if ($ind_ref) {
        return @$ind_ref;
    } else {
        return (4,5);   # Start + End in GFF
    }
}

sub outline_color {
    my ($self, $color) = @_;

    if ($color) {
	    $self->{'_outline_color'} = $color;
    }

    return $self->{'_outline_color'};
}

sub render {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $file = $band->feature_file
        or confess "feature_file not set";
    my $global_offset = $vc->chr_start - 1;

    open my $fh, $file or confess "Can't open '$file' : $!";
    my @ind = $band->start_end_column_indices;

    my $height    = $band->height;
    my $canvas    = $band->canvas;
    my $y_offset  = $band->y_offset;
    my $rpp       = $band->residues_per_pixel;
    my $color     = $band->band_color;
    my $outline_color = defined($band->outline_color) ? $band->outline_color : $color;
    my @tags      = $band->tags;
    
    $canvas->createRectangle(
        0, $y_offset, $band->width, $y_offset + $height,
        -fill       => undef,
        -outline    => undef,
        -tags       => [@tags],
        );

    my $y1 = $y_offset + 1;
    my $y2 = $y_offset + $height - 1;

    while (<$fh>) {
        next if /^\s*#/;
        next if /^\s*$/;

        # Cunning or what!
        my ($start, $end) = map $_ -= $global_offset, (split /\s+/, $_)[@ind];
        warn "Start End = $start\t$end\n";

	    next if $end < 1;
	    next if $start > $vc->length;
    
        my $x1 = $start / $rpp;
        my $x2 = $end   / $rpp;

        $canvas->createRectangle(
            $x1, $y_offset, $x2, $y2,
            #-fill       => $color,
            -fill       => 'LightSteelBlue',
            -outline    => 'black',
            -width      => 0.5,
            -tags       => [@tags],
            );
    }
    close $fh;
}




1;

__END__

=head1 NAME - GenomeCanvas::Band::FileFeatures

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

