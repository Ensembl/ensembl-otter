=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Test::Bio::Otter::Lace::CloneSequence;

use Test::Class::Most
    parent     => 'OtterTest::Class';

use Test::Bio::Vega::ContigInfo no_run_test => 1;

sub build_attributes {
    return {
        accession     => 'A12345',
        sv            => 6,
        clone_name    => 'RP11-299J5',
        contig_name   => 'AL234567.12.1.123456',
        chromosome    => '7',
        assembly_type => 'chr7-38',
        chr_start     => 8_020_404,
        chr_end       => 8_987_654,
        contig_start  => 100,
        contig_end    => 123_456,
        contig_strand => -1,
        length        => 123_357,
        # sequence      => 'GATACCAAAAA', # accessor dies on read if not set
        contig_id           => 'Contig-ID',         # redundant accessor?
        super_contig_name   => 'Super-Contig-Name', # redundant accessor?
        pipeline_chromosome => 'Pipe-Chr',          # redundant accessor?
        ContigInfo          => sub { return Test::Bio::Vega::ContigInfo->new->test_object },
        pipelineStatus      => sub { return bless {}, 'Bio::Otter::Lace::PipelineStatus' },
    };
}

sub sequence : Test(3) {
    my $test = shift;
    my $cs = $test->our_object;
    can_ok $cs, 'sequence';
    throws_ok { $cs->sequence } qr/sequence\(\) not set/, '...and throws if sequence not set';
    $cs->sequence('GATACAAAAA');
    is $cs->sequence, 'GATACAAAAA',                       '...and setting its value should succeed';
}

sub accession_dot_sv : Test(2) {
    my $test = shift;
    my $cs = $test->our_object;
    can_ok $cs, 'accession_dot_sv';
    $test->set_attributes;
    is $cs->accession_dot_sv, 'A12345.6', '...and its value should match';
    return;
}

sub drop_pipelineStatus : Test(4) {
    my $test = shift;
    $test->set_attributes;
    my $pls = $test->object_accessor( pipelineStatus => 'Bio::Otter::Lace::PipelineStatus' );
    my $cs = $test->our_object;
    can_ok $cs, 'drop_pipelineStatus';
    $cs->drop_pipelineStatus;
    is $cs->pipelineStatus, undef, '...it can be dropped';
    return;
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    $test->attributes_are($test->our_object,
                          {
                              accession     => $parsed_xml->{accession},
                              sv            => $parsed_xml->{version},
                              clone_name    => $parsed_xml->{clone_name},
                              contig_name   => $parsed_xml->{id},
                              chromosome    => $parsed_xml->{chromosome},
                              assembly_type => $parsed_xml->{assembly_type}, # needs to be injected
                              chr_start     => $parsed_xml->{assembly_start},
                              chr_end       => $parsed_xml->{assembly_end},
                              contig_start  => $parsed_xml->{fragment_offset},
                              # This may not always work:
                              contig_end    => $parsed_xml->{fragment_offset}
                                                + $parsed_xml->{assembly_end} - $parsed_xml->{assembly_start},
                              contig_strand => $parsed_xml->{fragment_ori},
                              length        => $parsed_xml->{clone_length},
                          },
                          $description);
    return;
}

1;

# EOF
