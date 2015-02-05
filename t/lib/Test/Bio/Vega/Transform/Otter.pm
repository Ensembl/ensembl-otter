package Test::Bio::Vega::Transform::Otter;

use Test::Class::Most
    parent     => 'Test::Bio::Vega::Transform',
    attributes => [ qw( xml_string parsed_xml ) ];

use List::Util qw(min max);
use OtterTest::TestRegion;

sub build_attributes {
    my $test = shift;
    return { };
}

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

    my $bvto = $test->our_object();
    can_ok $bvto, 'get_Analysis';

    my $an = $bvto->get_Analysis('otter-module-test');
    isa_ok $an, 'Bio::EnsEMBL::Analysis';
    is $an->logic_name, 'otter-module-test', '... logic_name';

    return;
}

sub get_ChrCoordSystem : Test(4) {
    my $test = shift;

    my $bvto = $test->our_object();
    can_ok $bvto, 'get_ChrCoordSystem';

    my $cs = $bvto->get_ChrCoordSystem;
    isa_ok $cs, 'Bio::EnsEMBL::CoordSystem';
    is $cs->name,    'chromosome', '... name';
    is $cs->version, 'Otter',      '... version';

    return;
}

sub get_ChromosomeSlice : Test(7) {
    my $test = shift;

    my $bvto = $test->our_object();
    can_ok $bvto, 'get_ChromosomeSlice';

    my $csl = $bvto->get_ChromosomeSlice;
    isa_ok $csl, 'Bio::EnsEMBL::Slice';

    my $parsed = $test->parsed_xml;
    my $sequence_set = $parsed->{sequence_set};

    is $csl->seq_region_name, $sequence_set->{assembly_type}, '... seq_region_name';
    is $csl->start,  min(map { $_->{assembly_start} } @{$sequence_set->{sequence_fragment}}), '... start';
    is $csl->end,    max(map { $_->{assembly_end} }   @{$sequence_set->{sequence_fragment}}), '... end';
    is $csl->strand, 1, '... strand';
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
        is $cs[$i]->chr_start, $sequence_frags->[$i]->{assembly_start}, '... chr_start';
    }

    return;
}

1;
