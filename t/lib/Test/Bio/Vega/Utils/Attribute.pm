=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Test::Bio::Vega::Utils::Attribute;

use Test::Class::Most
    parent     => 'OtterTest::Class';

use Bio::EnsEMBL::Transcript;

# This is a bit clunky, we could do with a non-OO parent class to handle critic and use_ok
# more cleanly.

BEGIN {
    __PACKAGE__->use_imports(
        [ qw( add_EnsEMBL_Attributes make_EnsEMBL_Attribute get_first_Attribute_value get_name_Attribute_value ) ]
        );
};

# because not OO, we need to also import here into this test class
BEGIN { use Bio::Vega::Utils::Attribute @{__PACKAGE__->use_imports()} }

sub build_attributes { return; } # none

sub setup       { return; }  # don't let OtterTest::Class do its OO stuff
sub constructor { return; }  # --"--

sub t1_make_EnsEMBL_Attribute : Tests {
    my $test = shift;
    my $a = make_EnsEMBL_Attribute('my_key' => 'my_value');
    isa_ok($a, 'Bio::EnsEMBL::Attribute');
    is($a->code,  'my_key',   'code');
    is($a->value, 'my_value', 'value');
    return;
}

sub t2_add_EnsEMBL_Attributes : Tests {
    my $test = shift;

    my $t = Bio::EnsEMBL::Transcript->new;
    add_EnsEMBL_Attributes($t, 'my_key' => 'my_value');
    pass('add a single attribute');

    my $attrs = $t->get_all_Attributes;
    is(@$attrs, 1, '... now has one attribute');
    my $a = $attrs->[0];
    is($a->code,  'my_key',   '...   code');
    is($a->value, 'my_value', '...   value');

    add_EnsEMBL_Attributes($t,
                           'key_2' => 'value_2',
                           'key_3' => 'value_3',
        );
    pass('add two more attributes');

    $attrs = $t->get_all_Attributes;
    is(@$attrs, 3, '... now has 3 attributes');

    my @results = map { [ $_->code => $_->value ] } @$attrs;
    cmp_deeply(\@results,
              bag(
                  [ 'my_key' => 'my_value' ],
                  [ 'key_2'  => 'value_2'  ],
                  [ 'key_3'  => 'value_3'  ],
              ),
              '... and attributes as expected');

    add_EnsEMBL_Attributes($t,
                           'my_key' => 'my_value_too',
                           'my_key' => 'my_value_3',
        );
    pass('add two more attributes with repeated key');

    $attrs = $t->get_all_Attributes;
    is(@$attrs, 5, '... now has 5 attributes');

    @results = map { [ $_->code => $_->value ] } @$attrs;
    cmp_deeply(\@results,
              bag(
                  [ 'my_key' => 'my_value'     ],
                  [ 'my_key' => 'my_value_too' ],
                  [ 'my_key' => 'my_value_3'   ],
                  [ 'key_2'  => 'value_2'      ],
                  [ 'key_3'  => 'value_3'      ],
              ),
              '... and attributes as expected');

    return;
}

sub t3_get_first_Attribute_value : Tests {
    my $test = shift;

    my $t = Bio::EnsEMBL::Transcript->new;
    my $get = get_first_Attribute_value($t, 'my_key');
    is($get, undef, 'get attribute, none');

    add_EnsEMBL_Attributes($t, 'my_key' => 'my_value');
    $get = get_first_Attribute_value($t, 'my_key');
    is($get, 'my_value', 'get attribute, only one');

    add_EnsEMBL_Attributes($t, 'my_key' => 'my_second_value');
    $get = get_first_Attribute_value($t, 'my_key');
    is($get, 'my_value', 'get attribute, first of two');

    throws_ok { get_first_Attribute_value($t, 'my_key', confess_if_multiple => 1) }
              qr/Got 2 'my_key' Attributes/, 'confess if multiple';

    return;
}

sub t4_get_name_Attribute_value : Tests {
    my $test = shift;

    my $t = Bio::EnsEMBL::Transcript->new;
    my $get = get_name_Attribute_value($t);
    is($get, undef, 'get attribute, none');

    add_EnsEMBL_Attributes($t, 'name' => 'Frederico');
    $get = get_name_Attribute_value($t);
    is($get, 'Frederico', 'get attribute, only one');

    add_EnsEMBL_Attributes($t, 'name' => 'Johannes');
    $get = get_name_Attribute_value($t);
    is($get, 'Frederico', 'get attribute, first of two');

    throws_ok { get_name_Attribute_value($t, confess_if_multiple => 1) }
              qr/Got 2 'name' Attributes/, 'confess if multiple';

    return;
}

1;
