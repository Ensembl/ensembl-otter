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


### Bio::Otter::Mapping::Map

package Bio::Otter::Mapping::Map;

# This class represents a mapping from a remote assembly to a local
# one.  It supports mappings made of multiple remote chromosomes
# (although in most cases there will be only one).  For each remote
# chromosome the mapping defines a number of maplets.  A maplet
# defines (a) the start and end of an interval, (b) an offset that
# translates the interval to the corresponding interval on the local
# chromosome, and (c) the relative orientation of the intervals.

# The start and end coordinates are relative to the remote chromosome.
# The offset maps the remote chromosome to the local chromosome, so
# that you add the offset to convert remote coordinates to local
# coordinates and subtract the offset to go back.  The orientation is
# -1 when the mapping reverses the direction of the interval and 1
# when it does not.

# $self = {
#   -map => [
#     {
#       chr => <name_of_remote_chromosome>,
#       maplet => [
#         start  => <integer>
#         end    => <integer>
#         offset => <integer>
#         ori    => [1|-1]
#       ],
#       ...
#     },
#     ...
#   ],
# }

use strict;
use warnings;

use Carp;

use List::Util qw( min max );

sub new {
    my ($pkg, @args) = @_;
    return bless { @args }, $pkg;
}

# we keep some properties of the maplet in lexical variables to save
# passing them as arguments for each feature

my (
    $_maplet,
    $_maplet_start,
    $_maplet_end,
    $_offset,
    $_is_reversed,
    );

sub _reflect {
    return ( $_maplet_end - ( $_ - $_maplet_start ) );
}

sub range_reflect {
    my @range = @_;
    return
        $_is_reversed
        ? ( map { _reflect } reverse @range )
        : @range;
}

sub range_local_to_remote {
    my @range = @_;
    $_ -= $_offset for @range;
    @range = range_reflect @range;
    return @range
}

sub range_remote_to_local {
    my @range = @_;
    @range = range_reflect @range;
    $_ += $_offset for @range;
    return @range
}

sub do_features {
    my ($self, $source, $start_local, $end_local, $target) = @_;

    for my $map (@{$self->{-map}}) {
        my $chr = $map->{chr};
        for my $maplet (@{$map->{maplet}}) {

            (
             $_maplet,
             $_maplet_start,
             $_maplet_end,
             $_offset,
             $_is_reversed,
            ) =
            (
             $maplet,
             $maplet->{start},
             $maplet->{end},
             $maplet->{offset},
             ( $maplet->{ori} == -1 ),
            );

            # calculate the minimal range to fetch, since fetching the entire
            # maplet may retrieve many unwanted features (testing shows that
            # this optimisation avoids a huge performance hit in some cases)

            my ( $start_remote, $end_remote ) =
                range_local_to_remote $start_local, $end_local;
            my $start = max $start_remote, $_maplet_start;
            my $end   = min $end_remote,   $_maplet_end;

            if ( $start <= $end ) {
                for ( @{$source->features($chr, $start, $end)} ) {
                    my @range = range_remote_to_local $_->start, $_->end;
                    $target->($_, @range);
                }
            }

        }
    }

    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Mapping::Map

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

