#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use CriticModule;

use Readonly;
use Test::More;

Readonly my %expected => {
    'M' => { class => 'Match',      desc => 'match',                   q => 10, t => 10 },
    'C' => { class => 'Codon',      desc => 'codon',                   q => 10, t => 10 },
    'G' => { class => 'Gap',        desc => 'gap',                     q => 10, t =>  0 },
    'N' => { class => 'NER',        desc => 'non-equivalenced region', q => 10, t => 10 },
    '5' => { class => 'SS_5P',      desc => "5' splice site",          q => 10, t => 10 },
    '3' => { class => 'SS_3P',      desc => "3' splice site",          q => 10, t => 10 },
    'I' => { class => 'Intron',     desc => 'intron',                  q => 10, t => 10 },
    'S' => { class => 'SplitCodon', desc => 'split codon',             q => 10, t => 10 },
    'F' => { class => 'Frameshift', desc => 'frameshift',              q => 10, t => 10 },
};

my ($ele_module, $ga_module);
BEGIN {
    $ga_module = 'Bio::Otter::GappedAlignment';
    use_ok($ga_module);
    $ele_module = 'Bio::Otter::GappedAlignment::Element';
    use_ok($ele_module);
}

critic_module_ok($ga_module);
critic_module_ok($ele_module);
critic_module_ok($ga_module . '::ElementI');
critic_module_ok($ga_module . '::ElementTypes');

foreach my $type (keys %expected) {
    my $exp = $expected{$type};
    my $ele = $ele_module->new($type, $exp->{q}, $exp->{t});
    my $class = $ele_module . '::' . $exp->{class};
    isa_ok($ele, $class);
    is($ele->type, $type, "type for $type");
    is($ele->long_type, $exp->{desc}, "long_type for $type");
    critic_module_ok($class);
}

my $ga = $ga_module->from_vulgar('Q 0 20 + T 6 21 + 56 M 5 5 G 3 0 M 5 5 G 0 1 M 4 4 G 3 0');
isa_ok($ga, 'Bio::Otter::GappedAlignment');
is($ga->query_id, 'Q', 'query_id');
is($ga->query_start, 0, 'query_start');
is($ga->query_end, 20, 'query_end');
is($ga->query_strand, '+', 'query_strand');
is($ga->target_id, 'T', 'target_id');
is($ga->target_start, 6, 'target_start');
is($ga->target_end, 21, 'target_end');
is($ga->target_strand, '+', 'target_strand');
is($ga->score, 56, 'score');
is($ga->n_elements, 6, 'n_elements');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
