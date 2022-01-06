=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::Band::SNP

package GenomeCanvas::Band::SNP;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');


sub new {
    my( $pkg ) = @_;
    
    my $band = $pkg->SUPER::new;
    $band->band_color('#d76918');
    $band->height(90);
    return $band;
}

sub render {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig;
    $band->draw_SNPs_on_virtual_contig($vc);
}

sub chr_snp_file {
    my( $self, $file ) = @_;
    
    if ($file) {
        $self->{'_chr_snp_filename'} = $file;
    }
    return $self->{'_chr_snp_filename'};
}

sub simplify {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_simplify_flag'} = $flag;
    }
    return $self->{'_simplify_flag'} || 0;
}

sub max_snp_density {
    my ($self, $max) = @_;

    if (defined $max) {
	$self->{'_max_snp_density'} = $max;
    }
    return $self->{'_max_snp_density'} || 50;
}

sub draw_SNPs_on_virtual_contig {
    my( $band, $vc ) = @_;
    
    my $max_expected_snps = $band->max_snp_density;
    my $height = $band->height;
    my $half_height = $height / 2;
    my $snp_height  = $half_height / $max_expected_snps;
    
    my @tags        = $band->tags;
    my $rpp         = $band->residues_per_pixel;
    my $y_offset    = $band->y_offset;
    my $color       = $band->band_color;
    my $canvas      = $band->canvas;
    my $width       = $band->width;

    my @outline = (0, $y_offset, $width, $y_offset + $height);
    $y_offset += $half_height;

    # Left axis
    $band->tick_label($max_expected_snps,   'w', 0,       $y_offset - $half_height);
    $band->tick_label(0,                    'w', 0,       $y_offset);
    $band->tick_label($max_expected_snps,   'w', 0,       $y_offset + $half_height);
    # Right axis
    $band->tick_label($max_expected_snps,   'e', $width,  $y_offset - $half_height);
    $band->tick_label(0,                    'e', $width,  $y_offset);
    $band->tick_label($max_expected_snps,   'e', $width,  $y_offset + $half_height);
    
    my $offset = $vc->chr_start - 1;
    my $length = $vc->length;
    
    my $snp_file = $band->chr_snp_file;
    my $binsize = $rpp / 2;

    $band->title( $band->title()."\nper $binsize bp" );
        
    my $bin = $binsize;
    my( @snp_count );

    if (open(SNPS, $snp_file)) {
	while(<SNPS>) {
	    /^\#/ and next;
	    my ($start) = (split)[3];
	    next if $start < $vc->chr_start or $start > $vc->chr_end;
	    $start -= $offset;

	    my $i = int($start / $binsize);
	    $snp_count[$i]++;
	}
	close(SNPS);
    }
    else {
	foreach my $snp ($vc->get_all_SimpleFeatures_by_feature_type('variation')) {
	    my $start = $snp->start;
	    my $i = int($start / $binsize);
	    $snp_count[$i]++;
	}
    }

    my $max_points = 200;
    my( @fwd_coords, @rev_coords );
    my ($max, $maxi) = (0,0);
    #my $simplify = $band->simplify;
    for (my $i = 0; $i < @snp_count;) {
        my $count = $snp_count[$i] || 0;
        if ($count > $max) {
	    $max = $count;
	    $maxi = $i;
	}
	$count = $max_expected_snps if $count > $max_expected_snps;

        my $bin_width = 1;

        $i += $bin_width;
        
        my $x1 = ( $i               * $binsize) / $rpp;
        my $x2 = (($i + $bin_width) * $binsize) / $rpp;
        my $y_fwd = $y_offset - ($snp_height * $count);
        my $y_rev = $y_offset + ($snp_height * $count);
        push   (@fwd_coords, $x1, $y_fwd, $x2, $y_fwd);
        unshift(@rev_coords, $x2, $y_rev, $x1, $y_rev);
                
        if (@fwd_coords % $max_points == 0 or $i == $#snp_count) {
            $canvas->createPolygon(
                @fwd_coords, @rev_coords,
                -outline    => undef,
                -fill       => $color,
                -tags       => [@tags],
                );
            @fwd_coords = ();
            @rev_coords = ();
        }
    }

    $band->draw_sequence_gaps;

    $canvas->createRectangle(
        @outline,
        -outline    => 'black',
        -width      => 1,
        -fill       => undef,
        -tags       => [@tags],
        );

    warn "max snp count = $max (at $maxi)\n";
}



1;

__END__

=head1 NAME - GenomeCanvas::Band::SNP

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

