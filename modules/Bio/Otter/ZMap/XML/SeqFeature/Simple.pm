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


## no critic (Modules::RequireFilenameMatchesPackage)

package Hum::Ace::SeqFeature::Simple; # mix-in!

use strict;
use warnings;
use Hum::XmlWriter;

sub zmap_xml_feature_tag {
    my ($self, $offset) = @_;

    $offset ||= 0;

    my $xml = Hum::XmlWriter->new;
    $xml->full_tag('feature', [     # Note: using array ref, not hash ref, to preserve order of attributes
        name        => $self->text,
        start       => $offset + $self->seq_start,
        end         => $offset + $self->seq_end,
        strand      => $self->seq_strand == -1 ? '-' : '+',
        style       => $self->Method->style_name,
        score       => 1 * $self->score,    # 0.5 comes from acedb as 0.500000 making old feature appear different to new
        ontology    => 'misc_feature',
    ]);
    return $xml->flush;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

