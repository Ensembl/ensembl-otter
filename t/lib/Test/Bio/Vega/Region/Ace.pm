=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

package Test::Bio::Vega::Region::Ace;

use Test::Class::Most
    parent     => 'Test::Bio::Vega';

use File::Temp qw( tempdir tempfile );

use OtterTest::AceDatabase;

sub test_bio_vega_features { return { test_region => 1, parsed_region => 1 }; }
sub build_attributes       { return; } # no test_attributes tests required

# DUP with Store.pm
sub teardown {
    my $test = shift;
    Bio::EnsEMBL::Registry->clear; # nasty nasty caches!
    $test->SUPER::teardown;
    return;
}

# Null test: expected and actual are both now fetched by make_assembly - Doh!

# sub make_assembly : Test(25) {  # n = 1 + 6 * @make_assembly_regions
#     my $test = shift;

#     my $bvra = $test->our_object;
#     can_ok $bvra, 'make_assembly';

#     # FIXME: duplication (now only of intent) with T:B:V:Region::Store

#     my @make_assembly_regions = (
#         undef,                      # use default human_test:chr2-38:929903-1379472
#         'human_test:chr6-38:2557766-2647766',
#         'human_test:chr12-38:30351955-34820185',
#         'mouse:chr1-38:3009920-3786391',
#         );

#     my $need_teardown_setup;
#     foreach my $test_region (@make_assembly_regions) {

#         if ($test_region or $need_teardown_setup) {
#             $test->teardown;
#             $test->test_region(OtterTest::TestRegion->new($test_region));
#             $test->setup;
#         }

#         $test->_do_make_assembly;

#         $need_teardown_setup = 1;
#     }

#     return;
# }

sub _do_make_assembly {
    my $test = shift;

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

    my $bvra = $test->our_object;

    my $ha = $bvra->make_assembly(
        $test->parsed_region,
        {
            name             => $test->test_region->xml_parsed->{'sequence_set'}->{'assembly_type'}, # FIXME
            MethodCollection => $adb->MethodCollection,
        },
        );
    isa_ok($ha, 'Hum::Ace::Assembly', '...and result of make_assembly()');

    subtest 'assembly' => sub {
        eq_or_diff($ha->ace_string, $ea->ace_string, 'ace_string matches');
        cmp_deeply($ha,
                   listmethods(
                       name          => [ $ea->name ],
                       assembly_name => [ $ea->assembly_name ],
                       species       => [ $ea->species ],
                       Sequence      => [ $ea->Sequence ],
                   ),
                   'deep');
    };

    my @e_SimpleFeatures = $ea->get_all_SimpleFeatures;
    my @h_SimpleFeatures = $ha->get_all_SimpleFeatures;
    is (scalar(@h_SimpleFeatures), scalar(@e_SimpleFeatures), '...n(SimpleFeatures)');

    subtest 'SimpleFeatures' => sub {
        unless (@e_SimpleFeatures) {
            pass 'No SimpleFeatures';
            return;
        }
        foreach my $i ( 0 .. $#e_SimpleFeatures ) {

            my $e_sf = $e_SimpleFeatures[$i];
            my $h_sf = $h_SimpleFeatures[$i];
            my $n_sf = "SimpleFeature[$i]";

            unless ($h_sf) {
                fail "$n_sf missing";
                next;
            }
            eq_or_diff($h_sf->ace_string, $e_sf->ace_string, "$n_sf ace_string");
            ok(exists $h_sf->{_ensembl_dbID}, "$n_sf has ensembl_dbID");
            delete $h_sf->{_ensembl_dbID}; # pre cmp_deeply()
            if (my $e_score = $e_sf->score) {
                my $tol = abs($h_sf->score - $e_score) / $e_score;
                ok($tol < 0.0000001, '$n_sf score');
                delete $e_sf->{_score};
                delete $h_sf->{_score};
            }
            cmp_deeply($h_sf, $e_sf, "$n_sf deeply");
        }
    };

    my @e_clones = $ea->get_all_Clones;
    my @h_clones = $ha->get_all_Clones;
    is (scalar(@h_clones), scalar(@e_clones), '...n(Clones)');

    subtest 'clones' => sub {
        foreach my $i ( 0 .. $#e_clones ) {
            unless ($h_clones[$i]) {
                fail "clone[$i] missing";
                next;
            }
            eq_or_diff($h_clones[$i]->ace_string, $e_clones[$i]->ace_string, "clone[$i] ace_string");
            cmp_deeply($h_clones[$i], $e_clones[$i], "clone[$i] deeply");
        }
    };

    my @e_loci = $ea->get_all_Loci;
    my @h_loci = $ha->get_all_Loci;
    is (scalar(@h_loci), scalar(@e_loci), '...n(Loci)');

    subtest 'loci' => sub {

        foreach my $i ( 0 .. $#e_loci ) {

            my $e_locus = $e_loci[$i];
            my $h_locus = $h_loci[$i];
            my $n_locus = "Locus[$i]";

            unless ($h_locus) {
                fail "$n_locus missing";
                next;
            }
            eq_or_diff($h_locus->ace_string, $e_locus->ace_string, "$n_locus ace_string");
            ok(exists $h_locus->{_ensembl_dbID}, "$n_locus has ensembl_dbID");
            delete $h_locus->{_ensembl_dbID};
            # cmp_deeply occurs via SubSeqs
            # cmp_deeply($h_locus, $e_locus, "$n_locus deeply");
        }
    };

    my @e_subseqs = $ea->get_all_SubSeqs;
    my @h_subseqs = $ha->get_all_SubSeqs;
    is (scalar(@h_subseqs), scalar(@e_subseqs), '...n(SubSeqs)');

    subtest 'subseqs' => sub {
        foreach my $i ( 0 .. $#e_subseqs ) {

            my $e_subseq = $e_subseqs[$i];
            my $h_subseq = $h_subseqs[$i];
            my $n_subseq = "SubSeq[$i]";

            unless ($h_subseq) {
                fail "$n_subseq missing";
                next;
            }
            eq_or_diff($h_subseq->ace_string, $e_subseq->ace_string, "$n_subseq ace_string");

            ok(exists $h_subseq->{_ensembl_dbID}, "$n_subseq has ensembl_dbID");
            delete $h_subseq->{_ensembl_dbID};

            my @e_exons = $e_subseq->get_all_Exons;
            my @h_exons = $h_subseq->get_all_Exons;
            is (scalar(@h_exons), scalar(@e_exons), "$n_subseq n_Exons");
            subtest 'exons' => sub {
                foreach my $i ( 0 .. $#e_exons ) {
                    unless ($h_exons[$i]) {
                        fail "Exon[$i] missing";
                        next;
                    }

                    ok(exists $h_exons[$i]->{_ensembl_dbID}, "Exon[$i] has ensembl_dbID");
                    delete $h_exons[$i]->{_ensembl_dbID};

                    # cmp_deeply happens below
                }
            };

            cmp_deeply($h_subseq, $e_subseq, "$n_subseq deeply");
        }
    };

    return;
}

1;
