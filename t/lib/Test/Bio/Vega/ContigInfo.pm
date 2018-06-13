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
