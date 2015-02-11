package Test::Bio::Vega::Evidence;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return {
        name => 'A121415',
        type => 'ncRNA',
    };
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    my $evi = $test->our_object;
    $test->attributes_are($evi,
                          {
                              name => $parsed_xml->{name},
                              type => $parsed_xml->{type},
                          },
                          "$description (attributes)");
    return;
}

1;
