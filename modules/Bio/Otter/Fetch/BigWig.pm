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


### Bio::Otter::Fetch::BigWig

package Bio::Otter::Fetch::BigWig;

use strict;
use warnings;
use Try::Tiny;
use Carp;
use Data::Dumper;
use Bio::DB::BigWig qw( binMean );

use Bio::Otter::Fetch::BigWig::Feature;

my $bin_size = 40;

sub new {
    my ($pkg, @args) = @_;
    return bless { @args }, $pkg;
}

sub features {
    my ($self, $chr, $start, $end) = @_;
    my $bigwig = $self->bigwig;
    my $seq_id = $self->seq_id_from_chr($chr);

    my $size = ($end + 1 - $start);
    my $bin_count = $size / $bin_size;
    return unless $bin_count;

    my ($summary) =
        $bigwig->features(
            -type   => 'summary',
            -seq_id => $seq_id,
            -start  => $start,
            -end    => $end,
        );

    my $features = [ ];
    my $index = 0;

    try{
        for my $bin (@{$summary->statistical_summary($bin_count)} ) {
            if ($bin->{validCount} > 0) {
               my $score = binMean($bin);
               my $feature_start =
                   $start + ( $index * ( $end + 1 - $start ) ) / $bin_count;
               my $feature_end =
                   ( $start + ( ( $index + 1 ) * ( $end + 1 - $start ) ) / $bin_count ) - 1;
               my $feature = Bio::Otter::Fetch::BigWig::Feature->new(
                   start  => $feature_start,
                   end    => $feature_end,
                   score  => $score,
                   );
               push @{$features}, $feature;
            }
        $index++;
        }
    };

    return $features;
}

# The seq_ids in many bigWig files prepend "chr" to the name of the
# chromosome so we look for both "$chr" and "chr${chr}".

sub seq_id_from_chr {
    my ($self, $chr) = @_;

    my $seq_id_hash = { };
    $seq_id_hash->{$_}++ for $self->bigwig->seq_ids;
    for ( $chr, "chr${chr}" ) {
        return $_ if $seq_id_hash->{$_};
    }

    croak sprintf "no such seq_id: '%s'", $chr;
}

# attributes

sub bigwig {
    my ($self) = @_;
    my $bigwig = $self->{'-bigwig'};
    return $bigwig;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::BigWig

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

