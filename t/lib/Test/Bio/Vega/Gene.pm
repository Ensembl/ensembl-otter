package Test::Bio::Vega::Gene;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return;
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    $test->attributes_are($test->our_object,
                          {
                              stable_id   => $parsed_xml->{stable_id},
                              description => $parsed_xml->{description},
                          },
                          $description);
    return;
}

1;
