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

1;

# EOF
