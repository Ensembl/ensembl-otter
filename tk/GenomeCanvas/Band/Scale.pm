
### GenomeCanvas::Band::Scale

package GenomeCanvas::Band::Scale;

use strict;
use Carp;
use GenomeCanvas::Band;

use vars '@ISA';
@ISA = ('GenomeCanvas::Band');


sub render {
    my( $band ) = @_;
    
    my $y_offset    = $band->y_offset;
    my $height      = $band->height;
    my $width       = $band->width;
    my @tags        = $band->tags;
    
    my $y_max = $y_offset;

    my $vc = $band->virtual_contig;
    my $chr_start  = $vc->chr_start;
    my $seq_length = $vc->length;
    my $seq_end = $chr_start + $seq_length;
    my $rpp = $band->residues_per_pixel;

    # Choose minumum space between labeled ticks based on font size
    my $min_interval = $rpp * $band->font_size * 4;
    my $interval = 1;
    my $multiplier = 5;
    while ($interval < $min_interval) {
        $interval *= $multiplier;
        $multiplier = ($multiplier == 5) ? 2 : 5;
    }
    my $precision = 7 - length($interval);
    #warn "interval = $interval, precision = $precision";
    {
        my( $i );
        if (my $rem = $chr_start % $interval) {
            $i = $chr_start - $rem + $interval;
        } else {
            $i = $chr_start;
        }
        #warn "First label = $i";

	# added by klh 020507: increased size of horizontal scale by 2
	my $saved_font = $band->font_size;
	$band->font_size( $saved_font + 2 );

        for (; $i <= $seq_end; $i += $interval) {
            my $Mbp = sprintf("%.${precision}f", $i / 1e6);
            $band->tick_label($Mbp, 's', ($i - $chr_start) / $rpp, $y_max);
        }

	$band->font_size( $saved_font );
    }

    my $canvas = $band->canvas;
    my $outline = $canvas->createLine(
        0, $y_max, $width, $y_max,
        -fill       => 'black',
        -width      => 1,
        -tags       => [@tags],
        );
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::Scale

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

