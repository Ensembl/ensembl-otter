=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Test::Bio::Vega::Transform::XMLToRegion;

use Test::Class::Most
    parent     => 'Test::Bio::Vega';

use Test::Bio::Vega::Region no_run_test => 1;

sub test_bio_vega_features             { return { test_region => 1, parsed_region => 1 }; }
sub get_bio_vega_transform_xmltoregion { return shift->our_object; }

sub build_attributes                   { return; }

sub parse : Test(5) {
    my $test = shift;

    my $bvt_x2r = $test->our_object;
    can_ok $bvt_x2r, 'parse';

    my $region = $test->parsed_region;
    isa_ok($region, 'Bio::Vega::Region', '...and result of parse()');

    my $parsed = $test->test_region->xml_parsed;
    is $region->species, $parsed->{species}, '...and species ok';

    my $t_region = Test::Bio::Vega::Region->new(our_object => $region);
    $t_region->matches_parsed_xml($test, $test->test_region->xml_parsed, 'region from parse');

    # region's coord_systems
    my $e_cs = $test->our_object()->coord_system_factory->coord_system('chromosome');
    is $region->slice->coord_system, $e_cs, 'region slice coord_system';

    return;
}

1;
