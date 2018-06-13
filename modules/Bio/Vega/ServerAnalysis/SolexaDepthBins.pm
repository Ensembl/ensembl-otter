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

### Bio::Vega::ServerAnalysis::SolexaDepthBins

package Bio::Vega::ServerAnalysis::SolexaDepthBins;

use strict;
use warnings;
use base qw{ Bio::Vega::ServerAnalysis };

use Bio::EnsEMBL::SimpleFeature;

my $BIN_SIZE = 10;

sub depth_feature {
    my ($slice, $strand, $bin, $score) = @_;

    my $start = $bin * $BIN_SIZE;
    my $end   = $start + ($BIN_SIZE - 1);
    my $display_label = sprintf("Average depth: %.2f", $score);

    my $depth_feature =
        Bio::EnsEMBL::SimpleFeature->new(
            -start         => $start,
            -end           => $end,
            -strand        => $strand,
            -slice         => $slice,
            -score         => $score,
            -display_label => $display_label,
        );

    return $depth_feature;
}

sub depth_features {
    my ($slice, $strand, $depth_hash) = @_;
    my @depth_features = map {
        depth_feature($slice, $strand, $_, $depth_hash->{$_});
    } keys %{$depth_hash};
    return @depth_features;
}

sub run {
    my ($self, $features) = @_;

    my $depth_features = [];

    if (@{$features}) {

        my $depth_forward = { };
        my $depth_reverse = { };

        for my $feature (@{$features}) {
            my $depth = $feature->strand == 1 ? $depth_forward : $depth_reverse; 
            for my $ungapped_feature ($feature->ungapped_features) {

                my $start = $ungapped_feature->start;
                my $end   = $ungapped_feature->end + 1;
                my $start_bin = int ($start / $BIN_SIZE);
                my $end_bin   = int ($end   / $BIN_SIZE);

                if ($start_bin == $end_bin) {
                    $depth->{$start_bin} += ($end - $start) / $BIN_SIZE;
                }
                else {
                    $depth->{$start_bin} += ($BIN_SIZE - $start % $BIN_SIZE) / $BIN_SIZE;
                    for (my $bin = $start_bin + 1; $bin < $end_bin; $bin++) {
                        $depth->{$bin}++;
                    }
                    $depth->{$end_bin} += ($end % $BIN_SIZE) / $BIN_SIZE;
                }
            }
        }

        my $slice = $features->[0]->slice;
        my @strand_depth_hash_list = (
            [ +1, $depth_forward ],
            [ -1, $depth_reverse ],
            );
        @$depth_features =
            map { depth_features($slice, @{$_}) } @strand_depth_hash_list;

    }

    return $depth_features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

