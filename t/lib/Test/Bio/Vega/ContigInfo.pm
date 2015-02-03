package Test::Bio::Vega::ContigInfo;

use Test::Class::Most
    parent     => 'OtterTest::Class';

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

1;

# EOF
