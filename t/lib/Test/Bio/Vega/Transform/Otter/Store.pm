package Test::Bio::Vega::Transform::Otter::Store;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::Transform::Otter',
    attributes => test_db;

use OtterTest::DB;

use Bio::Vega::Region;
use Bio::Vega::Transform::XML;

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
    $test->test_db($test->_get_test_db());
    $test->SUPER::setup;
    return;
}

sub _get_test_db {
    return OtterTest::DB->new_with_dataset_info(dataset_name => 'human_test');
}

sub teardown {
    my $test = shift;
    $test->test_db(undef);
    Bio::EnsEMBL::Registry->clear; # nasty nasty caches!
    $test->SUPER::teardown;
    return;
}

# Override the our_object() accessor to set vega_dba after construction
#
sub our_object {
    my ($test, @args) = @_;
    my $our_object = $test->SUPER::our_object;
    if (@args) {
        $test->SUPER::our_object(@args);
        $our_object = $test->SUPER::our_object;
        $our_object->vega_dba($test->test_db->vega_dba);
    }
    return $our_object;
}

sub store : Test(8) {
    my $test = shift;

    # First with standard object and test region
    $test->_store_extract_compare;

    # Now re-run with the first simpler region

    $test->teardown;

    $test->test_region(OtterTest::TestRegion->new(0));
    $test->setup;

    $test->_store_extract_compare;

    return;
}

sub _store_extract_compare {
    my $test = shift;
    my $bvtos = $test->our_object;
    can_ok $bvtos, 'store';
    $bvtos->store($test->test_region->fake_dna());
    pass '... stored';

    my $original_slice = $bvtos->get_ChromosomeSlice;
    # FIXME : we do this quite a lot:
    my $sa = $test->test_db->vega_dba->get_SliceAdaptor;
    my $seq_region = $sa->fetch_by_region($original_slice->coord_system->name, $original_slice->seq_region_name);
    my $slice = $seq_region->sub_Slice($original_slice->start, $original_slice->end);

    my $region = Bio::Vega::Region->new_from_otter_db(
        otter_dba => $test->test_db->vega_dba,
        slice     => $slice,
        );

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

    my $xml_writer = Bio::Vega::Transform::XML->new;
    $xml_writer->region($region);
    my $xml_out = $xml_writer->generate_OtterXML;
    chomp $xml_out;
    ok $xml_out, '... regenerate XML';
    eq_or_diff $xml_out, $test->test_region->xml_region, '... XML matches';

    return;
}

1;
