package Test::Bio::Vega::Region::Ace;

use Test::Class::Most
    parent     => 'Test::Bio::Vega';

use File::Temp qw( tempdir );

use OtterTest::AceDatabase;

sub test_bio_vega_features { return { test_region => 1, parsed_region => 1 }; }
sub build_attributes       { return; } # no test_attributes tests required

sub make_ace_string : Tests {
    my $test = shift;

    my $bvra = $test->our_object;
    can_ok $bvra, 'make_ace_string';

    my $ace = $bvra->make_ace_string($test->parsed_region);
    ok ($ace, '... produces output');
    note ("ace_string (first 2000 chrs):\n", substr($ace, 0, 2000));

    return;
}

sub make_assembly : Tests {
    my $test = shift;

    my $bvra = $test->our_object;
    can_ok $bvra, 'make_assembly';

    my $tmpdir = tempdir('B:V:R:Ace.make_assembly.XXXXXX', TMPDIR => 1, CLEANUP => 1);

    my $adb = OtterTest::AceDatabase->new_from_region(
        "$tmpdir/acedb",
        'B:V:R:Ace.make_assembly',
        $test->parsed_region,
        );
    my $ea = $adb->fetch_assembly;

    my $ha = $bvra->make_assembly(
        $test->parsed_region,
        {
            name             => $test->test_region->xml_parsed->{'sequence_set'}->{'assembly_type'}, # FIXME
            MethodCollection => $adb->MethodCollection,
        },
        );
    isa_ok($ha, 'Hum::Ace::Assembly', '...and result of make_assembly()');

    eq_or_diff($ha->ace_string, $ea->ace_string, '...and ace_string matches');

    my @e_clones = $ea->get_all_Clones;
    my @h_clones = $ha->get_all_Clones;
    is (scalar(@h_clones), scalar(@e_clones), '...n(Clones)');

    subtest 'clones' => sub {
        foreach my $i ( 0 .. $#e_clones ) {
            fail "clone[$i] missing" unless $h_clones[$i];
            eq_or_diff($h_clones[$i]->ace_string, $e_clones[$i]->ace_string, "clone[$i] ace_string");
        }
    };

    return;
}

1;
