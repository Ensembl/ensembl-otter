=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::DensityBand::SNP

package GenomeCanvas::DensityBand::SNP;

use strict;
use Carp;
use GenomeCanvas::DensityBand;
use GenomeCanvas::GD_StepMap;

use vars '@ISA';
@ISA = ('GenomeCanvas::DensityBand');

sub render {
    my( $band ) = @_;
    
    $band->draw_snps;
    $band->draw_sequence_gaps;
    $band->draw_outline_and_labels;
}

sub max_snp_count {
    my( $band, $max ) = @_;
    
    if ($max) {
        $band->{'_max_snp_count'} = $max;
    }
    return $max || 30;
}

sub draw_snps {
    my( $band ) = @_;

    my $rpp = $band->residues_per_pixel;
    my $vc  = $band->virtual_contig;    
    my $offset      = $vc->chr_start - 1;
    my $seq_length  = $vc->length;
        
    my $snp_file = $band->chr_snp_file or confess "chr_snp_file not set";
    my $binsize = $rpp;
    my $bin = $binsize;
    my( @snp_count );
    local *SNP_FILE;
    open SNP_FILE, $snp_file or confess "Can't read '$snp_file' : $!";
    while (<SNP_FILE>) {
        my ($start, $end) = map $_ - $offset, (split)[3,4];
        next if $end < 1;
        next if $start > $seq_length;
        my $i = int($start / $binsize);
        $snp_count[$i]++;
    }
    close SNP_FILE;

    # Check for clipping of density map
    my $max_count = 0;
    foreach my $i (grep $_, @snp_count) {
        $max_count = $i if $i > $max_count;
    }
    warn "max SNP count = $max_count\n";
    my $max_density = $band->max_snp_count;
    if ($max_count > $max_density) {
        warn "Clipping: max count '$max_count' > max density '$max_density'";
    }

    my $length = int($seq_length / $rpp);
    for (my $i = 0; $i < $length; $i++) {
        $snp_count[$i] ||= 0;
    }

    my $map = GenomeCanvas::GD_StepMap->new($length, $band->height);
    $map->range(0, 35);
    my $color = $band->band_color;
    $map->color($color);
    $map->mvalues(@snp_count);

    # Add the png to the image
    my $canvas = $band->canvas;
    my $image = $canvas->Photo(
        '-format'   => 'png',
        -data       => $map->base64_png,
        );
    my $y_offset    = $band->y_offset;
    my @tags        = $band->tags;
    $canvas->createImage(
        0, $y_offset + 0.5,    # Off-by-1 error when placing images?
        -anchor     => 'nw',
        -image      => $image,
        -tags       => [@tags],
        );
}


sub chr_snp_file {
    my( $self, $file ) = @_;
    
    if ($file) {
        $self->{'_chr_snp_filename'} = $file;
    }
    return $self->{'_chr_snp_filename'};
}


1;

__END__

=head1 NAME - GenomeCanvas::DensityBand::SNP

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

