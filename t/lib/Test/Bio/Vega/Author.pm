package Test::Bio::Vega::Author;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return {
        name  => 'mg13',
        # email => 'mg13@sanger.ac.uk',
        group => sub { return bless {}, 'Bio::Vega::AuthorGroup' },
    };
}

sub email : Test(3) {
    my $test = shift;
    $test->set_attributes;
    my $author = $test->our_object;
    can_ok $author, 'email';
    is $author->email, $author->name, '... and default is name';
    $author->email('mg13@sanger.ac.uk');
    is $author->email, 'mg13@sanger.ac.uk', '... and setting its value succeeds';
    return;
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    $test->attributes_are($test->our_object,
                          {
                              name  => $parsed_xml->{author},
                              email => $parsed_xml->{author_email},
                          },
                          $description);
    return;
}

1;
