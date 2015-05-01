package Test::Bio::Vega::Region::Ace;

use Test::Class::Most
    parent     => 'Test::Bio::Vega';

sub test_bio_vega_features { return { test_region => 1, parsed_region => 1 }; }
sub build_attributes       { return; } # no test_attributes tests required

sub make_ace_string : Tests {
    my $test = shift;

    my $bvra = $test->our_object;
    can_ok $bvra, 'make_ace_string';

    my $ace = $bvra->make_ace_string($test->parsed_region);
    ok ($ace, '... produces output');
    note ("ace_string (first 200 chrs):\n", substr($ace, 0, 200));

    return;
}

sub make_assembly : Tests {
    my $test = shift;

    my $bvra = $test->our_object;
    can_ok $bvra, 'make_assembly';

    my $ha = $bvra->make_assembly(
        $test->parsed_region,
        {
            name             => $test->test_region->xml_parsed->{'sequence_set'}->{'assembly_type'}, # FIXME
            MethodCollection => bless {}, 'Hum::Ace::MethodCollection', # FIXME
        },
        );
    isa_ok($ha, 'Hum::Ace::Assembly', '...and result of make_assembly()');
    note("ace_string:\n", $ha->ace_string);

    return;
}

1;
