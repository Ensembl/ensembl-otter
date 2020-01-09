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

package Test::Bio::Vega::Exon;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return {
        stable_id      => 'OTTETEST000567',
        start          => 3_123_456,
        end            => 3_123_789,
        strand         => 1,
        phase          => 2,
        end_phase      => -1,   # FIXME? test for warning
        analysis       => sub { return bless {}, 'Bio::EnsEMBL::Analysis' },
    };
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    my $exon = $test->our_object;
    note "stable_id '$parsed_xml->{stable_id}'";
    $test->attributes_are($exon,
                          {
                              stable_id        => $parsed_xml->{stable_id},
                              seq_region_start => $parsed_xml->{start},
                              seq_region_end   => $parsed_xml->{end},
                              strand           => $parsed_xml->{strand},
                              phase            => $parsed_xml->{phase},
                              end_phase        => $parsed_xml->{end_phase},
                          },
                          "$description (attributes)");
    return;
}

1;
