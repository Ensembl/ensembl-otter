package Test::Bio::Vega::Utils::Attribute;

use Test::Class::Most
    parent     => 'OtterTest::Class';

use Bio::EnsEMBL::Transcript;

# This is a bit clunky, we could do with a non-OO parent class to handle critic and use_ok
# more cleanly.

BEGIN { OtterTest::Class->use_imports( [ qw( add_EnsEMBL_Attributes make_EnsEMBL_Attribute ) ] ) };

# because not OO, we need to also import here into this test class
BEGIN { use Bio::Vega::Utils::Attribute @{OtterTest::Class->use_imports()} }

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

    my $attrs = $t->get_all_Attributes;
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

1;
