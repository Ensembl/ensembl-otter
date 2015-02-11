package Test::Bio::Vega::Exon;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return {
        stable_id      => 'OTTETEST000567',
        start          => 3_123_456,
        end            => 3_123_789,
        strand         => 1,
        phase          => 2,
        end_phase      => -1,   # FIXME? test for warning
        analysis       => sub { return bless {}, 'Bio::EnsEMBL::Analysis' },
    };
}

sub matches_parsed_xml {
    my ($test, $parsed_xml, $description) = @_;
    my $exon = $test->our_object;
    note "stable_id '$parsed_xml->{stable_id}'";
    $test->attributes_are($exon,
                          {
                              stable_id        => $parsed_xml->{stable_id},
                              seq_region_start => $parsed_xml->{start},
                              seq_region_end   => $parsed_xml->{end},
                              strand           => $parsed_xml->{strand},
                              phase            => $parsed_xml->{phase},
                              end_phase        => $parsed_xml->{end_phase},
                          },
                          "$description (attributes)");
    return;
}

1;
