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

package Bio::Otter::ServerAction::TSV::FindClones;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction::FindClones';

=head1 NAME

Bio::Otter::ServerAction::TSV::FindClones - server requests to find clones, serialised via TSV

=cut

sub serialise_output {
    my ($self, $results) = @_;

    my $tsv_string = '';
    $tsv_string .= "\tToo many search results, some were omitted - please be more specific\n"
      if $self->result_overflow;

    while (my ($qname, $qname_results) = each %{$results}) {
        while (my ($chr_name, $chr_name_results) = each %{$qname_results}) {
            while (my ($qtype, $qtype_results) = each %{$chr_name_results}) {
                while (my ($components, $count) = each %{$qtype_results}) {
                    $tsv_string .=
                        join("\t", $qname, $qtype, $components, $chr_name)."\n";
                }
            }
        }
    }

    return $tsv_string;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
