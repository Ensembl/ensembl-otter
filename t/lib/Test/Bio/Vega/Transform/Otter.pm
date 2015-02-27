package Test::Bio::Vega::Transform::Otter;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::Transform',
    attributes => [ qw( xml_string parsed_xml ) ];

use Test::Bio::Otter::Lace::CloneSequence no_run_test => 1;
use Test::Bio::Vega::Gene                 no_run_test => 1;

use OtterTest::TestRegion;

sub build_attributes { return; }

sub startup : Tests(startup => +0) {
    my $test = shift;
    $test->SUPER::startup;

    $test->xml_string(OtterTest::TestRegion::local_xml_copy());
    $test->parsed_xml(OtterTest::TestRegion::local_xml_parsed());

    return;
}

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;

    my $bvto = $test->our_object;
    $bvto->parse($test->xml_string);

    return;
}

sub parse : Test(2) {
    my $test = shift;

    my $bvto = $test->our_object;
    can_ok $bvto, 'parse';

    my $parsed = $test->parsed_xml;
    is $bvto->species, $parsed->{species}, '...and species ok';

    return;
}

sub get_Analysis : Test(3) {
    my $test = shift;
    my $an = $test->object_accessor( get_Analysis => 'Bio::EnsEMBL::Analysis', 'otter-module-test' );
    is $an->logic_name, 'otter-module-test', '... logic_name';
    return;
}

sub get_ChrCoordSystem : Test(4) {
    my $test = shift;
    my $cs = $test->object_accessor( get_ChrCoordSystem => 'Bio::EnsEMBL::CoordSystem' );
    is $cs->name,    'chromosome', '... name';
    is $cs->version, 'Otter',      '... version';
    return;
}

sub get_ChromosomeSlice : Test(7) {
    my $test = shift;

    my $csl = $test->object_accessor( get_ChromosomeSlice => 'Bio::EnsEMBL::Slice' );

    my $parsed = $test->parsed_xml;
    my $sequence_set = $parsed->{sequence_set};

    my ($start, $end) = OtterTest::TestRegion::local_xml_bounds();

    is $csl->seq_region_name, $sequence_set->{assembly_type}, '... seq_region_name';
    is $csl->start,  $start, '... start';
    is $csl->end,    $end,   '... end';
    is $csl->strand, 1, '... strand';

    my $bvto = $test->our_object();
    is $csl->coord_system, $bvto->get_ChrCoordSystem, '... coord_system';

    return;
}

sub get_CloneSequences : Tests {
    my $test = shift;

    my $bvto = $test->our_object();
    can_ok $bvto, 'get_CloneSequences';

    my @cs = $bvto->get_CloneSequences;

    my $parsed = $test->parsed_xml;
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

sub get_Genes : Tests {
    my $test = shift;

    my $genes = $test->object_accessor( get_Genes => 'ARRAY' );

    my $parsed = $test->parsed_xml;
    my $loci   = $parsed->{sequence_set}->{locus};

    my $n = scalar @$genes;
    is $n,  scalar @$loci, '... n(Genes)';

    foreach my $i ( 0..$n-1 ) {
        isa_ok $genes->[$i], 'Bio::Vega::Gene', "... Gene[$i]";

        my $locus = $loci->[$i];
        my $t_gene = Test::Bio::Vega::Gene->new(our_object => $genes->[$i]);
        $t_gene->matches_parsed_xml($locus, "... Gene[$i]");
    }

    return;
}

sub get_SimpleFeatures : Tests {
    my $test = shift;

    my $genes = $test->object_accessor( get_Genes => 'ARRAY' );
    return;
}

1;
