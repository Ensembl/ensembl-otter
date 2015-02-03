package Test::Bio::Otter::Lace::CloneSequence;

use Test::Class::Most          # automagically becomes my parent
    attributes => [ qw( clone_sequence ) ];

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

sub class { return 'Bio::Otter::Lace::CloneSequence' };

sub startup : Tests(startup) {
    my $test  = shift;
    my $class = $test->class;
    eval "use $class";
    die $@ if $@;
    return;
}

sub setup : Tests(setup) {
    my $test = shift;
    my $class = $test->class;
    $test->clone_sequence($class->new);
    return;
}

sub _critic : Test(1) {
    my $test = shift;
    my $class = $test->class;
    critic_module_ok($class);
    return;
}

sub constructor : Test(3) {
    my $test = shift;
    my $class = $test->class;
    can_ok $class, 'new';
    ok my  $cs = $class->new, '... and the constructor should succeed';
    isa_ok $cs,  $class,      '... and the object it returns';
    return;
}

sub attributes {
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
        # ContigInfo          => contig_info_obj,     # takes object
        # pipelineStatus      => pipeline_status_obj, # takes object
    };
}

sub test_attributes : Test(45) {
    my $test = shift;
    my $attributes = $test->attributes;
    foreach my $a ( keys %$attributes ) {
        $test->_attribute($a, $attributes->{$a});
    }
    return;
}

sub sequence : Test(3) {
    my $test = shift;
    my $cs = $test->clone_sequence;
    can_ok $cs, 'sequence';
    throws_ok { $cs->sequence } qr/sequence\(\) not set/, '...and throws if sequence not set';
    $cs->sequence('GATACAAAAA');
    is $cs->sequence, 'GATACAAAAA',                       '...and setting its value should succeed';
}

sub accession_dot_sv : Test(2) {
    my $test = shift;
    my $cs = $test->clone_sequence;
    can_ok $cs, 'accession_dot_sv';
    $test->_set_attributes;
    is $cs->accession_dot_sv, 'A12345.6', '...and its value should match';
    return;
}

sub _attribute {
    my ($test, $attribute, $expected) = @_;
    $test->setup;
    my $cs = $test->clone_sequence;
    can_ok $cs, $attribute;
    ok ! defined $cs->$attribute, "...and '$attribute' should start out undefined";
    $test->_set_attributes;
    is $cs->$attribute, $expected,'...and setting its value should succeed';
    return;
}

sub _set_attributes {
    my $test = shift;
    my $cs = $test->clone_sequence;
    my $attributes = $test->attributes;
    foreach my $a ( keys %$attributes ) {
        $cs->$a($attributes->{$a});
    }
    return;
}

1;

# EOF
