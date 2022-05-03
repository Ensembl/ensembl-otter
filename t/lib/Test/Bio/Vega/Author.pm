=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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
