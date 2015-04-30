package Test::Bio::Vega::Region::Ace;

use Test::Class::Most
    parent     => 'Test::Bio::Vega';

use File::Temp qw( tempdir tempfile );

use OtterTest::AceDatabase;

sub test_bio_vega_features { return { test_region => 1, parsed_region => 1 }; }
sub build_attributes       { return; } # no test_attributes tests required

sub make_ace_string : Tests {
    my $test = shift;

    my $bvra = $test->our_object;
    can_ok $bvra, 'make_ace_string';

    # quick check on _process_contig_attribs for 'annotated'
    my $cs = ($test->parsed_region->clone_sequences)[0];
    $cs->ContigInfo->add_Attributes(Bio::EnsEMBL::Attribute->new(-CODE => 'annotated', -VALUE => 'T'));

    my $ace = $bvra->make_ace_string($test->parsed_region);
    ok ($ace, '... produces output');

    $test->_save_ace('make_ace_string', $ace);

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

    # $adb has already fetched DNA, so we pluck it from there for our test region.
    # YUCK: playing with EnsEMBL internals:
    $test->parsed_region->slice->{'seq'} = $ea->Sequence->sequence_string;

    my $ha = $bvra->make_assembly(
        $test->parsed_region,
        {
            name             => $test->test_region->xml_parsed->{'sequence_set'}->{'assembly_type'}, # FIXME
            MethodCollection => $adb->MethodCollection,
        },
        );
    isa_ok($ha, 'Hum::Ace::Assembly', '...and result of make_assembly()');

    my $ace_string = $ha->ace_string;
    eq_or_diff($ace_string, $ea->ace_string, '...and ace_string matches');

    my @e_clones = $ea->get_all_Clones;
    my @h_clones = $ha->get_all_Clones;
    is (scalar(@h_clones), scalar(@e_clones), '...n(Clones)');

    subtest 'clones' => sub {
        foreach my $i ( 0 .. $#e_clones ) {
            unless ($h_clones[$i]) {
                fail "clone[$i] missing";
                next;
            }
            my $clone_ace_string = $h_clones[$i]->ace_string;
            $ace_string .= $clone_ace_string;
            eq_or_diff($clone_ace_string, $e_clones[$i]->ace_string, "clone[$i] ace_string");
            cmp_deeply($h_clones[$i], $e_clones[$i], "clone[$i] deeply");
        }
    };

    my @e_subseqs = $ea->get_all_SubSeqs;
    my @h_subseqs = $ha->get_all_SubSeqs;
    is (scalar(@h_subseqs), scalar(@e_subseqs), '...n(SubSeqs)');

    subtest 'subseqs' => sub {
        foreach my $i ( 0 .. $#e_subseqs ) {
            unless ($h_subseqs[$i]) {
                fail "SubSeq[$i] missing";
                next;
            }
            my $substr_ace_string = $h_subseqs[$i]->ace_string;
            $ace_string .= $substr_ace_string;
            eq_or_diff($substr_ace_string, $e_subseqs[$i]->ace_string, "SubSeq[$i] ace_string");
            cmp_deeply($h_subseqs[$i], $e_subseqs[$i], "SubSeq[$i] deeply");
        }
    };

    $test->_save_ace('make_assembly', $ace_string);

    return;
}

sub _save_ace {
    my ($test, $desc, $ace_string) = @_;

    my ($fh, $filename) = tempfile("B:V:R:Ace.${desc}.XXXXXX", TMPDIR => 1, CLEANUP => 0, SUFFIX => '.ace');
    print $fh $ace_string;
    close $fh;

    diag("Ace for '$desc' saved to: $filename");
    return;
}

1;
