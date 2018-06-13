=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Test::Bio::Vega::Region::Store;

use Test::Class::Most
    parent     => 'Test::Bio::Vega', # not Test::Bio::Vega::Region as we are not a subclass
    attributes => [ qw( test_db coord_system_factory ) ];

use OtterTest::DB;

use Bio::Vega::CoordSystemFactory;
use Bio::Vega::Region;
use Bio::Vega::Transform::RegionToXML;

sub test_bio_vega_features { return { test_region => 1, parsed_region => 1 }; }
sub build_attributes       { return; } # no test_attributes tests required


# These fixtures will move into a parent class or role at some stage
#
sub startup {
    my $test = shift;
    # We set a throw-away DB to make sure we can, before going any further
    $test->_get_test_db;
    $test->SUPER::startup;
    return;
}

sub setup {
    my $test = shift;

    # test_db() and coord_system_factory() are needed to build our_object() in SUPER::setup
    #
    $test->test_db($test->_get_test_db());
    $test->get_coord_system_factory; # ensures coord_system_factory is instantiated

    $test->SUPER::setup;

    return;
}

sub _get_test_db {
    return OtterTest::DB->new_with_dataset_info(dataset_name => 'human_test');
}

sub teardown {
    my $test = shift;
    $test->test_db(undef);
    $test->coord_system_factory(undef);
    Bio::EnsEMBL::Registry->clear; # nasty nasty caches!
    $test->SUPER::teardown;
    return;
}

sub get_coord_system_factory {
    my $test = shift;

    my $cs_factory = $test->coord_system_factory;
    return $cs_factory if $cs_factory;

    $cs_factory = Bio::Vega::CoordSystemFactory->new( dba => $test->test_db->vega_dba, create_in_db => 1 );
    $test->coord_system_factory($cs_factory);
    return $cs_factory;
}

# We override the our_object() accessor to set vega_dba and coord_system_factory after construction
# (could do this via $test->our_args() now, instead)
#
sub our_object {
    my ($test, @args) = @_;
    my $our_object = $test->SUPER::our_object;
    if (@args) {
        $test->SUPER::our_object(@args);
        $our_object = $test->SUPER::our_object;
        $our_object->vega_dba($test->test_db->vega_dba);
        $our_object->coord_system_factory($test->coord_system_factory);
    }
    return $our_object;
}

sub store : Test(12) {
    my $test = shift;

    # First with standard object and test region
    $test->_store_extract_compare;

    # Now re-run with the first simpler region

    $test->teardown;

    $test->test_region(OtterTest::TestRegion->new(0));
    $test->setup;

    $test->_store_extract_compare;

    # And then with a humungous region

    $test->teardown;

    $test->test_region(OtterTest::TestRegion->new(2));
    $test->setup;

    $test->_store_extract_compare;

    return;
}

sub _store_extract_compare {
    my $test = shift;
    my $bvtos = $test->our_object;
    can_ok $bvtos, 'store';
    $bvtos->store($test->parsed_region, $test->test_region->fake_dna());
    pass '... stored';

    my $original_slice = $test->parsed_region->slice;
    # FIXME : we do this quite a lot:
    my $sa = $test->test_db->vega_dba->get_SliceAdaptor;
    my $seq_region = $sa->fetch_by_region($original_slice->coord_system->name, $original_slice->seq_region_name);
    my $slice = $seq_region->sub_Slice($original_slice->start, $original_slice->end);

    my $region = Bio::Vega::Region->new_from_otter_db( slice => $slice );

    # This is a bit yucky!
  GENE: foreach my $g ($region->genes) {
    ATTR: foreach my $ga ( @{$g->get_all_Attributes} ) {
        next ATTR unless $ga->code eq 'remark';
        my $value = $ga->value;
        if ($ga->value =~ /^Transcript .* has (no|\d+) exons+ /) {
            $g->truncated_flag(1);
            next GENE;
        }
    } # ATTR
  } # GENE

    my $xml_writer = Bio::Vega::Transform::RegionToXML->new;
    $xml_writer->region($region);
    my $xml_out = $xml_writer->generate_OtterXML;
    chomp $xml_out;
    ok $xml_out, '... regenerate XML';
    eq_or_diff $xml_out, $test->test_region->xml_region, '... XML matches';

    return;
}

1;
