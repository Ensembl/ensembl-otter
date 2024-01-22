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

package Test::Bio::Vega;

use Test::Class::Most
    parent      => 'OtterTest::Class',
    is_abstract => 1,
    attributes  => [ qw( test_region parsed_region ) ];

sub startup : Test(startup => +0) {
    my $test = shift;
    $test->SUPER::startup;

    my $features = $test->test_bio_vega_features;
    if ($features->{test_region} or $features->{parsed_region}) {
        require OtterTest::TestRegion;
        $test->test_region(OtterTest::TestRegion->new(1)); # we use the second more complex region
    }

    return;
}

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;

    my $features = $test->test_bio_vega_features;
    if ($features->{parsed_region}) {

        my $bvt_x2r = $test->get_bio_vega_transform_xmltoregion;
        $bvt_x2r->coord_system_factory($test->get_coord_system_factory);

        my $region = $bvt_x2r->parse($test->test_region->xml_region);
        $test->parsed_region($region);
    }

    return;
}

# Overrideable - default is a plain in-memory one
#
sub get_coord_system_factory {
    my ($test) = @_;
    require Bio::Vega::CoordSystemFactory;
    return Bio::Vega::CoordSystemFactory->new(%{$test->get_coord_system_factory_override_spec});
}

sub get_coord_system_factory_override_spec {
  my ($test) = @_;

  return {
    override_spec => {
      chromosome => { '-version' => 'Otter', '-rank' => 2, '-default' => 1,                         },
      clone      => {                        '-rank' => 4, '-default' => 1,                         },
      contig     => {                        '-rank' => 5, '-default' => 1,                         },
      dna_contig => { '-version' => 'Otter', '-rank' => 6, '-default' => 1, '-sequence_level' => 1, },
    }
  }
}
sub get_bio_vega_transform_xmltoregion {
    require Bio::Vega::Transform::XMLToRegion;
    return Bio::Vega::Transform::XMLToRegion->new;
}

sub test_bio_vega_features {
    return {
        test_region   => 0,
        parsed_region => 0,
    };
}

1;
