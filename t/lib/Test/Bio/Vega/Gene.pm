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

package Test::Bio::Vega::Gene;

use Test::Class::Most
    parent     => 'OtterTest::Class';

use Test::Bio::Vega::Author     no_run_test => 1;
use Test::Bio::Vega::Transcript no_run_test => 1;

use OtterTest::TestRegion;

sub build_attributes {
    my $test = shift;
    return {
        stable_id      => 'OTTTEST000123',
        description    => 'Test gene',
        start          => 3_456_000,
        end            => 3_567_899,
        strand         => -1,
        analysis       => sub { return bless {}, 'Bio::EnsEMBL::Analysis' },
        gene_author    => sub { return Test::Bio::Vega::Author->new->test_object },
        # source         => 'havana-test',
        # truncated_flag => 1,
    };
}

sub source : Test(3) {
    my $test = shift;
    my $gene = $test->our_object;
    can_ok $gene, 'source';
    is $gene->source, 'havana', '... and default is correct';
    $gene->source('test');
    is $gene->source, 'test',   '... and setting its value succeeds';
    return;
}

sub truncated_flag : Test(3) {
    my $test = shift;
    my $gene = $test->our_object;
    can_ok $gene, 'truncated_flag';
    is $gene->truncated_flag, 0, '... and default is correct';
    $gene->truncated_flag(1);
    is $gene->truncated_flag, 1, '... and setting its value succeeds';
    return;
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    my $gene = $test->our_object;
    my $gene_info = OtterTest::TestRegion->new(0)->gene_info_lookup($parsed_xml->{stable_id});
    note "stable_id '$parsed_xml->{stable_id}'";
    $test->attributes_are($gene,
                          {
                              stable_id   => $parsed_xml->{stable_id},
                              description => $parsed_xml->{description},
                              source      => $gene_info->{source},
                              biotype     => $gene_info->{biotype},
                              status      => $gene_info->{status},
                              truncated_flag => $parsed_xml->{truncated},
                          },
                          "$description (attributes)");

    subtest "$description (name)" => sub {
        my $na = $gene->get_all_Attributes('name');
        ok $na && scalar(@$na),                  'has name attribute';
        is $na->[0]->value, $parsed_xml->{name}, 'name matches';
    };

    my $t_author = Test::Bio::Vega::Author->new(our_object => $gene->gene_author);
    $t_author->matches_parsed_xml($parsed_xml, "$description (author)");

    my $transcripts = $gene->get_all_Transcripts;
    my $xml_ts = $parsed_xml->{transcript};

    my $n = scalar @$transcripts;
    is $n,  scalar @$xml_ts, 'n(Transcripts)';

    foreach my $i ( 0 .. $n-1 ) {
        isa_ok $transcripts->[$i], 'Bio::Vega::Transcript', "... Transcript[$i]";

        my $parsed_ts = $parsed_xml->{transcript}->[$i];
        my $t_ts = Test::Bio::Vega::Transcript->new(our_object => $transcripts->[$i]);
        $t_ts->matches_parsed_xml($parsed_ts, "... Transcript[$i]");
    }

    return;
}

1;
