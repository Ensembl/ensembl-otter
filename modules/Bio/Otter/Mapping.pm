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


### Bio::Otter::Mapping

package Bio::Otter::Mapping;

use XML::Simple;

use strict;
use warnings;

use Carp;
use Bio::Otter::Lace::Client;
sub _equiv_new { ## no critic (Subroutines::RequireArgUnpacking)
    require Bio::Otter::Mapping::Equiv;
    return Bio::Otter::Mapping::Equiv->new(@_);
}

sub _map_new { ## no critic (Subroutines::RequireArgUnpacking)
    require Bio::Otter::Mapping::Map;
    return Bio::Otter::Mapping::Map->new(@_);
}

sub new_from_otter {
    my ($pkg, $dataset, $csver_remote, $chr, $start, $end) = @_;
    if (defined $dataset && defined $csver_remote) {
        # get the mapping from the Otter server
        require Bio::Otter::Lace::Defaults;
        my $client = Bio::Otter::Lace::Defaults::make_Client();
        my $mapping_xml = $client->otter_response_content(
            'GET', 'get_mapping', {
                dataset => $dataset,
                cs      => $csver_remote,
                chr     => $chr,
                start   => $start,
                end     => $end,
                'author'=> $client->author,
            });
        my $mapping = $pkg->new_from_xml($mapping_xml);
        return $mapping;
    }
    if (! defined $dataset && ! defined $csver_remote) {
        my $mapping = _equiv_new('-chr' => $chr);
        return $mapping;
    }
    if (defined $dataset) {
        die "&new_from_otter: the '--dataset' parameter requires the '--csver_remote' parameter";
    }
    if (defined $csver_remote) {
        die "&new_from_otter: the '--csver_remote' parameter requires the '--dataset' parameter";
    }
    die "&new_from_otter: bug: should not reach this line";
}

sub new_from_xml {
    my ($pkg, $xml) = @_;

    local $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
    # configure expat for speed, also used in Bio::Vega::XML::Parser

    my $data =
        XMLin($xml,
              ForceArray => [ qw( map maplet ) ],
              KeyAttr => {
              },
        );
    my $type = $data->{type};
    die "missing mapping type" unless $type;

    return
        ( ! $type ) ? die "missing mapping type" :
        ( $type eq 'none'  ) ? die "there is no mapping" :
        ( $type eq 'equiv' ) ? _equiv_new( 
            -chr => $data->{equiv_chr},
        ) :
        ( $type eq 'map' ) ? _map_new(
            -map => $data->{map}
        ) :
            die "invalid mapping type '${type}'";

}

1;

__END__

=head1 NAME - Bio::Otter::Mapping

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

