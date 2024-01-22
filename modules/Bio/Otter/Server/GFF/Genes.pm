=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


package Bio::Otter::Server::GFF::Genes;

use strict;
use warnings;

use base qw( Bio::Otter::Server::GFF );

my @gff_keys = qw(
    gff_source
    gff_seqname
    url_string
    transcript_analyses
    );

sub get_requested_features {
    my ($self) = @_;

    my @analysis =
        $self->param('analysis')
        ? split(/,/, $self->param('analysis'))
        : (undef);

    # third parameter of $slice->get_all_Genes() helps
    # preventing lazy-loading of transcripts

    my $map = $self->make_map;
    my $metakey = $self->param('metakey');
    return [
        map {
            @{$self->fetch_mapped_features_ensembl('get_all_Genes', [ $_, undef, 1 ], $map, $metakey)};
        } @analysis ];
}

sub _gff_keys { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    return @gff_keys;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

