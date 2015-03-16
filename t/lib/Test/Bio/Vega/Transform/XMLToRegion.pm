package Test::Bio::Vega::Transform::XMLToRegion;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::XML::Parser',
    attributes => [ qw( test_region parse_result ) ];

use Test::Bio::Otter::Lace::CloneSequence no_run_test => 1;
use Test::Bio::Vega::Gene                 no_run_test => 1;

use OtterTest::TestRegion;

sub build_attributes { return; }

sub startup : Tests(startup => +0) {
    my $test = shift;
    $test->SUPER::startup;
    $test->test_region(OtterTest::TestRegion->new(1)); # we use the second more complex region
    return;
}

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;

    my $bvto = $test->our_object;
    my $region = $bvto->parse($test->test_region->xml_region);
    $test->parse_result($region);

    return;
}

sub parse : Test(3) {
    my $test = shift;

    my $bvto = $test->our_object;
    can_ok $bvto, 'parse';

    my $region = $test->parse_result;
    isa_ok($region, 'Bio::Vega::Region', '...and result of parse()');

    my $parsed = $test->test_region->xml_parsed;
    is $region->species, $parsed->{species}, '...and species ok';

    return;
}

sub get_ChrCoordSystem : Test(4) {
    my $test = shift;
    my $cs = $test->object_accessor( get_ChrCoordSystem => 'Bio::EnsEMBL::CoordSystem' );
    is $cs->name,    'chromosome', '... name';
    is $cs->version, 'Otter',      '... version';
    return;
}

# FIXME: we should be testing the Region now.
sub region_slice : Test(6) {
    my $test = shift;

    my $csl = $test->parse_result->slice;
    isa_ok($csl, 'Bio::EnsEMBL::Slice', 'region->slice');

    my $parsed = $test->test_region->xml_parsed;
    my $sequence_set = $parsed->{sequence_set};

    my ($start, $end) = $test->test_region->xml_bounds();

    is $csl->seq_region_name, $sequence_set->{assembly_type}, '... seq_region_name';
    is $csl->start,  $start, '... start';
    is $csl->end,    $end,   '... end';
    is $csl->strand, 1, '... strand';

    my $bvto = $test->our_object();
    is $csl->coord_system, $bvto->get_ChrCoordSystem, '... coord_system';

    return;
}

sub region_clone_sequences : Tests {
    my $test = shift;

    my @cs = $test->parse_result->sorted_clone_sequences;

    my $parsed = $test->test_region->xml_parsed;
    my $sequence_set = $parsed->{sequence_set};
    my $sequence_frags = [ sort { $a->{assembly_start} <=> $b->{assembly_start} }
                                @{$sequence_set->{sequence_fragment}}             ];

    my $n = scalar @cs;
    is $n,  scalar @$sequence_frags, '... n(CloneSequences)';
    foreach my $i ( 0..$n-1 ) {
        isa_ok $cs[$i], 'Bio::Otter::Lace::CloneSequence', "... CloneSequence[$i]";

        my $sf = $sequence_frags->[$i];
        $sf->{assembly_type} = $parsed->{assembly_type}; # inject into sequence_fragment

        my $t_cs = Test::Bio::Otter::Lace::CloneSequence->new(our_object => $cs[$i]);
        $t_cs->matches_parsed_xml($sf, "... CloneSequence[$i]");
    }
    return;
}

sub region_genes : Tests {
    my $test = shift;

    my @genes = $test->parse_result->genes;

    my $parsed = $test->test_region->xml_parsed;
    my $loci   = $parsed->{sequence_set}->{locus};

    my $n = scalar @genes;
    is $n,  scalar @$loci, '... n(Genes)';

    foreach my $i ( 0..$n-1 ) {
        isa_ok $genes[$i], 'Bio::Vega::Gene', "... Gene[$i]";

        my $locus = $loci->[$i];
        my $t_gene = Test::Bio::Vega::Gene->new(our_object => $genes[$i]);
        $t_gene->matches_parsed_xml($locus, "... Gene[$i]");
    }

    return;
}

sub seq_features : Tests {
    my $test = shift;

    my @features = $test->parse_result->seq_features;

    my $parsed = $test->test_region->xml_parsed;
    my $e_features = $parsed->{sequence_set}->{feature_set}->{feature};

    my $n = scalar @features;
    is $n,  scalar @$e_features, 'n(seq_features)';

    # FIXME: do some tests here!!
    return;
}

1;
