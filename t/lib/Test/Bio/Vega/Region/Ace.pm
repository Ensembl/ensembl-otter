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

1;
