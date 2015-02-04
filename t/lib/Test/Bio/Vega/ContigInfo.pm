package Test::Bio::Vega::ContigInfo;

use Test::Class::Most
    parent     => 'OtterTest::Class';

use Bio::EnsEMBL::Attribute;

sub build_attributes {
    my $test = shift;
    return {
        dbID => 9998,
        adaptor => sub { return bless {}, 'Bio::EnsEMBL::DBSQL::BaseAdaptor' },
        slice   => sub { return bless {}, 'Bio::EnsEMBL::Slice' },
        author  => sub { return bless {}, 'Bio::Vega::Author' },
        created_date => '2015-02-03 04:05:06',
    };
}

sub attributes : Test(6) {
    my $test = shift;
    my $ci = $test->our_object;

    can_ok $ci, 'get_all_Attributes';
    is_deeply $ci->get_all_Attributes, [], '...and list starts empty';

    can_ok $ci, 'add_Attributes';
    $ci->add_Attributes( bless { code => 'test' }, 'Bio::EnsEMBL::Attribute' );
    my $attr = $ci->get_all_Attributes;
    is scalar @$attr, 1, '...and we can add an attribute';
    $ci->add_Attributes(
        bless({ code => 'test_x' }, 'Bio::EnsEMBL::Attribute'),
        bless({ code => 'test' },   'Bio::EnsEMBL::Attribute'),
        );
    is scalar @{$ci->get_all_Attributes},         3, '...and we can add multiple attributes';
    is scalar @{$ci->get_all_Attributes('test')}, 2, '...and we can get them by attrib code';
    return;
}

1;

# EOF
