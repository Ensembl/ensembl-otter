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

package Test::Bio::Vega::Region;

use Test::Class::Most
    parent     => 'OtterTest::Class';

use Test::Bio::Otter::Lace::CloneSequence no_run_test => 1;
use Test::Bio::Vega::Gene                 no_run_test => 1;

sub build_attributes {
    my $test = shift;
    return {
        slice          => sub { return bless {}, 'Bio::EnsEMBL::Slice' },
        species        => 'human_test',
    };
}

sub genes : Test(4) {
    my $test = shift;
    my $region = $test->our_object;
    can_ok $region, 'genes';
    can_ok $region, 'add_genes';

    $region->add_genes(Test::Bio::Vega::Gene->new->test_object);
    my @genes = $region->genes;
    is scalar @genes, 1, '... and adding one gene works';

    $region->add_genes( bless {}, 'Bio::Vega::Gene' );
    @genes = $region->genes;
    is scalar @genes, 2, '... and adding another gene works';

    return;
}

sub seq_features : Test(4) {
    my $test = shift;
    my $region = $test->our_object;
    can_ok $region, 'seq_features';
    can_ok $region, 'add_seq_features';

    my $seq_feature1 = Test::Bio::Vega::Gene->new->test_object;
    $region->add_seq_features( bless {}, 'Bio::EnsEMBL::SimpleFeature' );
    my @seq_features = $region->seq_features;
    is scalar @seq_features, 1, '... and adding one seq_feature works';

    $region->add_seq_features( bless {}, 'Bio::EnsEMBL::SimpleFeature' );
    @seq_features = $region->seq_features;
    is scalar @seq_features, 2, '... and adding another seq_feature works';

    return;
}

sub clone_sequences : Test(10) {
    my $test = shift;
    my $region = $test->our_object;
    can_ok $region, 'clone_sequences';
    can_ok $region, 'add_clone_sequences';
    can_ok $region, 'sorted_clone_sequences';
    can_ok $region, 'chromosome_name';

    my $cs1 = Test::Bio::Otter::Lace::CloneSequence->new->test_object;
    $region->add_clone_sequences($cs1);
    my @clone_sequences = $region->clone_sequences;
    is scalar @clone_sequences, 1, '... and adding one clone_sequence works';
    is scalar($region->sorted_clone_sequences), 1, '... and sorted_clone_sequences works';

    my $cs2 = bless { %$cs1 }, 'Bio::Otter::Lace::CloneSequence';
    $cs2->chr_end(   $cs1->chr_start - 1 );
    $cs2->chr_start( $cs1->chr_start - 100_000 );
    $region->add_clone_sequences($cs2);
    @clone_sequences = $region->clone_sequences;
    is scalar @clone_sequences, 2, '... and adding another clone_sequence works';

    my @sorted = $region->sorted_clone_sequences;
    is scalar @sorted, 2, '... and n(sorted_clone_sequence)';
    is_deeply \@sorted, [ $cs2, $cs1 ], '... and sort order is correct';

    is $region->chromosome_name, $cs1->chromosome, '... chromosome_name()';

    return;
}

sub matches_parsed_xml {
    my ($test, $parent, $parsed_xml, $description) = @_;
    my $region = $test->our_object;

    subtest $description => sub {

        is $region->species, $parsed_xml->{species}, 'species';

        subtest 'slice' => sub {
            my $csl = $region->slice;
            isa_ok($csl, 'Bio::EnsEMBL::Slice');

            my $sequence_set = $parsed_xml->{sequence_set};

            my ($start, $end) = $parent->test_region->xml_bounds();

            is $csl->seq_region_name, $sequence_set->{assembly_type}, '... seq_region_name';
            is $csl->start,  $start, '... start';
            is $csl->end,    $end,   '... end';
            is $csl->strand, 1, '... strand';

        };

        subtest 'clone_sequences' => sub {
            my @cs = $region->sorted_clone_sequences;

            my $sequence_set = $parsed_xml->{sequence_set};
            my $sequence_frags = [ sort { $a->{assembly_start} <=> $b->{assembly_start} }
                                   @{$sequence_set->{sequence_fragment}}             ];

            my $n = scalar @cs;
            is $n,  scalar @$sequence_frags, '... n(CloneSequences)';
            foreach my $i ( 0..$n-1 ) {
                isa_ok $cs[$i], 'Bio::Otter::Lace::CloneSequence', "... CloneSequence[$i]";

                my $sf = $sequence_frags->[$i];
                $sf->{assembly_type} = $parsed_xml->{assembly_type}; # inject into sequence_fragment

                my $t_cs = Test::Bio::Otter::Lace::CloneSequence->new(our_object => $cs[$i]);
                $t_cs->matches_parsed_xml($sf, "... CloneSequence[$i]");
            }
        };

        subtest 'genes' => sub {
            my @genes = $region->genes;

            my $loci   = $parsed_xml->{sequence_set}->{locus};

            my $n = scalar @genes;
            is $n,  scalar @$loci, '... n(Genes)';

            foreach my $i ( 0..$n-1 ) {
                isa_ok $genes[$i], 'Bio::Vega::Gene', "... Gene[$i]";

                my $locus = $loci->[$i];
                my $t_gene = Test::Bio::Vega::Gene->new(our_object => $genes[$i]);
                $t_gene->matches_parsed_xml($locus, "... Gene[$i]");
            }
        };

        subtest 'seq_features' => sub {
            my @features = $region->seq_features;

            my $e_features = $parsed_xml->{sequence_set}->{feature_set}->{feature};

            my $n = scalar @features;
            is $n,  scalar @$e_features, 'n(seq_features)';

            # FIXME: do some tests here!!
        };
    };

    return;
}

1;
