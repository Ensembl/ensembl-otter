package Test::Bio::Vega::Transform::XMLToRegion;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::XML::Parser',
    attributes => [ qw( test_region parse_result ) ];

use Test::Bio::Vega::Region no_run_test => 1;

use OtterTest::TestRegion;

sub build_attributes { return; }

sub startup : Tests(startup => +0) {
    my $test = shift;
    $test->SUPER::startup;
    $test->test_region(OtterTest::TestRegion->new(1)); # we use the second more complex region
    return;
}

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;

    my $bvt_x2r = $test->our_object;
    my $region = $bvt_x2r->parse($test->test_region->xml_region);
    $test->parse_result($region);

    return;
}

sub parse : Test(5) {
    my $test = shift;

    my $bvt_x2r = $test->our_object;
    can_ok $bvt_x2r, 'parse';

    my $region = $test->parse_result;
    isa_ok($region, 'Bio::Vega::Region', '...and result of parse()');

    my $parsed = $test->test_region->xml_parsed;
    is $region->species, $parsed->{species}, '...and species ok';

    my $t_region = Test::Bio::Vega::Region->new(our_object => $region);
    $t_region->matches_parsed_xml($test, $test->test_region->xml_parsed, 'region from parse');

    # region's coord_systems
    my $bvt_x2r = $test->our_object();
    is $region->slice->coord_system, $bvt_x2r->get_ChrCoordSystem, 'region slice coord_system';

    return;
}

sub get_ChrCoordSystem : Test(4) {
    my $test = shift;
    my $cs = $test->object_accessor( get_ChrCoordSystem => 'Bio::EnsEMBL::CoordSystem' );
    is $cs->name,    'chromosome', '... name';
    is $cs->version, 'Otter',      '... version';
    return;
}

1;
