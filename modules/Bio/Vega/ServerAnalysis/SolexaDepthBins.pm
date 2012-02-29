### Bio::Vega::ServerAnalysis::SolexaDepthBins

package Bio::Vega::ServerAnalysis::SolexaDepthBins;

use strict;
use warnings;

use Data::Dumper;

use Bio::EnsEMBL::SimpleFeature;

my $BIN_SIZE = 10;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub run {
    my ($self, $features) = @_;

    my @depth_features;

    my $depth_forward = {};
    my $depth_reverse = {};

    my $slice;

    for my $af (@$features) {
        $slice ||= $af->slice;
        my $depth = $af->strand == 1 ? $depth_forward : $depth_reverse; 
        my @fs = $af->ungapped_features;
        for my $f (@fs) {
            for (my $i = $f->start; $i < $f->end; $i++) {
                $depth->{$i}++;    
            }
        }
    }

    for my $depth ($depth_forward, $depth_reverse) {

        my $strand = ($depth == $depth_forward ? 1 : -1);

        my ($start, $end, $tot_depth);

        my $bin_cnt = 0;

        for my $b (sort { $a <=> $b } keys %$depth) {

            my $depth = $depth->{$b};

            $bin_cnt++;

            if (!$start) {
                $start = $b;
                $end = $b;
                $tot_depth = $depth;
            }
            elsif ( ($bin_cnt == $BIN_SIZE) || ($b != $end+1) ) {

                # end this feature

                my $score = $tot_depth / ($end - $start +1);

                my $sf = Bio::EnsEMBL::SimpleFeature->new(
                    -start         => $start,
                    -end           => $end,
                    -strand        => $strand,
                    -slice         => $slice,
                    -score         => $score,
                    -display_label => sprintf("Average depth: %.2f", $score),
                );

                push @depth_features, $sf;

                $start = $b;
                $end = $b;
                $tot_depth = $depth;
                $bin_cnt = 0;
            }
            else {
                $end++;
                $tot_depth += $depth;
            }
        }
    }

    return @depth_features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

