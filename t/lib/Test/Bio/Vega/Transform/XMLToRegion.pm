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
    is $region->slice->coord_system->rank, $e_cs->rank, 'region slice coord_system';

    return;
}

1;
