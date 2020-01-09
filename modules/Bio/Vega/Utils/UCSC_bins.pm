=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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


### Bio::Vega::Utils::UCSC_bins

package Bio::Vega::Utils::UCSC_bins;

use strict;
use warnings;
use Carp;
use base 'Exporter';

our @EXPORT_OK = qw{
    smallest_bin_for_range
    all_bins_overlapping_range
    all_bins_overlapping_range_string_for_sql
};

### Remember the UCSC coordinate system when reading this code. In UCSC
### coordinates a feature with start = 9, end = 10 is a single base long feature
### located at the 10th base of the sequence.

sub smallest_bin_for_range {
    my ($start, $end) = @_;

    if ($end > 2**29) {
        # Range is beyond 512 Mbp of original UCSC algorithm
        return _smallest_bin_for_range_extended($start, $end);
    }
    else {
        return _smallest_bin_for_range_standard($start, $end);
    }
}

sub _smallest_bin_for_range_standard {
    my ($start, $end) = @_;

    my $start_bin = $start   >> 17;
    my $end_bin   = $end - 1 >> 17;

    foreach my $offset (512+64+8+1, 64+8+1, 8+1, 1, 0) {
        if ($start_bin == $end_bin) {
            return $offset + $start_bin;
        }
        $start_bin >>= 3;
        $end_bin   >>= 3;
    }
}

sub _smallest_bin_for_range_extended {
    my ($start, $end) = @_;

    my $start_bin = $start   >> 17;
    my $end_bin   = $end - 1 >> 17;

    foreach my $offset (4096+512+64+8+1, 512+64+8+1, 64+8+1, 8+1, 1, 0) {
        if ($start_bin == $end_bin) {
            # Need to add 4681 so that bins from extended don't clash with
            # standard bins.
            return 4681 + $offset + $start_bin;
        }
        $start_bin >>= 3;
        $end_bin   >>= 3;
    }
    die sprintf "Range %d to %d outside limit of 2 Gbp (%d)\n", $start, $end, 2**31;
}

sub all_bins_overlapping_range_string_for_sql {
    my ($start, $end) = @_;

    my $bins = all_bins_overlapping_range($start, $end);
    return join(',', @$bins);
}

sub all_bins_overlapping_range {
    my ($start, $end) = @_;

    if ($end > 2**29) {
        # Test is < not <= because $start is in zero based coordinates:
        if ($start < 2**29) {
            # A range overlapping the boundary between the standard and extended
            # binning systems.  Need to make sure we return any features that
            # fit in the last bin before the boundary under the standard scheme.
            my $std_bin = _all_bins_overlapping_range_standard($start, 2**29);
            my $exd_bin = _all_bins_overlapping_range_extended(2**29, $end);
            return [@$std_bin, @$exd_bin];
        }
        else {
            return _all_bins_overlapping_range_extended($start, $end);
        }
    }
    else {
        return _all_bins_overlapping_range_standard($start, $end);
    }
}

sub _all_bins_overlapping_range_standard {
    my ($start, $end) = @_;

    my $start_bin = $start   >> 17;
    my $end_bin   = $end - 1 >> 17;

    my $overlapping_bins = [];
    foreach my $offset (512+64+8+1, 64+8+1, 8+1, 1, 0) {
        push @$overlapping_bins, $offset + $start_bin .. $offset + $end_bin;
        $start_bin >>= 3;
        $end_bin   >>= 3;
    }

    return $overlapping_bins;
}

sub _all_bins_overlapping_range_extended {
    my ($start, $end) = @_;

    my $start_bin = $start   >> 17;
    my $end_bin   = $end - 1 >> 17;

    my $overlapping_bins = [];
    foreach my $offset (4096+512+64+8+1, 512+64+8+1, 64+8+1, 8+1, 1, 0) {
        push @$overlapping_bins, 4681 + $offset + $start_bin .. 4681 + $offset + $end_bin;
        $start_bin >>= 3;
        $end_bin   >>= 3;
    }

    return $overlapping_bins;
}


1;

__END__

=head1 NAME - Bio::Vega::Utils::UCSC_bins

=head1 DESCRIPTION

The UCSC binning scheme can be thought of as a kind of hashing algorithm,
whereby all coordinates within the same 128K (2^17) get the same number. The
idea is to create a small index that will return all overlapping features with
the range used by a typical chromsome - start - end query.

This is base on benchmarking work by Any Yates:

  See: https://gist.github.com/andrewyatz/cb318b06b1a5e0533078

I've put numbers in the code rather than using variables because I think it is
clearer, and the numbers should be inlined as constants for speed.

=head1 EXPORTED FUNCTIONS

Note that the start is expected to be in UCSC 0-based coordinates, so the
examples take 1 away from it:

  my $bin = smallest_bin_for_range($start - 1, $end);

Used when indexing a feature.

  my $bins_ref = all_bins_overlapping_range($start - 1, $end);

Return a list ref of all the bins needed in a query for fetching features
overlapping a range.

  my $string = all_bins_overlapping_range_string_for_sql($start - 1, $end);

Return a comma separated string of all bins needed in a query for fetching features.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

