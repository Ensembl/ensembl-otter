#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Test::More;
use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Text::sprintfn;

my ($vud_module, @subs);
BEGIN {
    $vud_module = 'Bio::Vega::Utils::Detaint';
    @subs = qw(
    detaint_url_fmt
    detaint_pfam_url_fmt
    detaint_sprintfn_url_fmt
    );
    use_ok($vud_module, @subs);
}
critic_module_ok($vud_module);

my $sprintfn_template = 'http://www.ensembl.org/%(species)s/Variation/Summary?v=%(id)s';

my @tests = (
    {
        name => 'plain',
        template => 'http://www.ensembl.org/Rattus_norvegicus/Location/View?gene=%s',
        expected => {
            detaint_url_fmt          => 1,
            detaint_pfam_url_fmt     => 1,
        },
    },
    {
        name => 'pfam',
        template => 'http://pfam.sanger.ac.uk/family?entry=%{pfam}',
        expected => {
            detaint_pfam_url_fmt     => 1,
        },
    },
    {
        name => 'sprintfn',
        template => $sprintfn_template,
        expected => {
            detaint_sprintfn_url_fmt => 1,
        },
    },
    {
        name => 'bad plain',
        template => "http://www.ensembl.org/Rattus_norvegicus/Location/View?gene=%s\nDELETE",
        expected => {},
    },
    {
        name => 'bad pfam',
        template => 'http://pfam.sanger.ac.uk/family?entry=%{pfam}/ cruft',
        expected => {},
    },
    {
        name => 'bad sprintfn',
        template => 'http://http://www.ensembl.org/%(species)x/Variation/Summary?v=%(id)s',
        expected => {},
    },
    );

foreach my $test ( @tests ) {
    subtest $test->{name} => sub {
        my $template = $test->{template};
        foreach my $detaint_sub ( @subs ) {
            my $should_succeed = $test->{expected}->{$detaint_sub};
            my $expected = $should_succeed ? $template : undef;
            my $e_state  = $should_succeed ? 'matches' : 'fails';
            no strict 'refs';
            is(&$detaint_sub($template), $expected, sprintf('%-25s (%-7s)', $detaint_sub, $e_state));
        }
    };
}

subtest 'Sane sprintfn format' => sub {
    is (sprintfn($sprintfn_template, { id => 'rs123456', species => 'Mus_musculus' }),
        'http://www.ensembl.org/Mus_musculus/Variation/Summary?v=rs123456',
        'substitutions'
        );
};

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
