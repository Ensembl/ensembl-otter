package Test::Bio::Vega::Transform::XMLToRegion;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::XML::Parser',
    attributes => [ qw( test_region parse_result ) ];

use Test::Bio::Vega::Region no_run_test => 1;

use OtterTest::TestRegion;
use Bio::Vega::CoordSystemFactory;

sub build_attributes { return; }

sub startup : Tests(startup => +0) {
    my $test = shift;
    $test->SUPER::startup;
    $test->test_region(OtterTest::TestRegion->new(1)); # we use the second more complex region

    return;
}

# Overrideable - default is a plain in-memory one
#
sub get_coord_system_factory {
    return Bio::Vega::CoordSystemFactory->new;
}

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;

    my $bvt_x2r = $test->our_object;
    $bvt_x2r->coord_system_factory($test->get_coord_system_factory);

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
    my $e_cs = $test->our_object()->coord_system_factory->coord_system('chromosome');
    is $region->slice->coord_system, $e_cs, 'region slice coord_system';

    return;
}

1;
