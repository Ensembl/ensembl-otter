package Test::Bio::Vega::Transform::Otter::Store;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::Transform::Otter',
    attributes => test_db;

use OtterTest::DB;
use OtterTest::TestRegion qw( local_xml_dna );

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
    return OtterTest::DB->new_with_dataset_info(dataset_name => 'human');
}

sub teardown {
    my $test = shift;
    $test->test_db(undef);
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

sub store : Test(2) {
    my $test = shift;
    my $bvtos = $test->our_object;
    can_ok $bvtos, 'store';
    $bvtos->store(local_xml_dna());
    pass '... stored';
    return;
}

1;
