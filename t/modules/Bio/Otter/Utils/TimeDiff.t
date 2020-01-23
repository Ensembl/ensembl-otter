#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;
use Test::Perl::Critic;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::TimeDiff';
    use_ok($module, 'time_diff_for');
}
critic_module_ok($module);
critic_ok(__FILE__);

do {
    local $SIG{__WARN__} = sub { note(@_) };
    time_diff_for( sub { sleep 1; } );
    pass('defaults');
};

{
    my @events;

    my $retval = time_diff_for(\&_test_timed, \&_test_logger, 'testing');

    is(scalar(@events), 4, 'n_events');
    is($retval, 'xyzzy', 'retval');
    is_deeply([map { $_->{event} }   @events], [qw( start in_test_timed end elapsed )], 'events');
    is_deeply([map { $_->{cb_data} } @events], [qw( testing ) x 4 ],                    'cb_data');

    sub _test_timed {
        push @events, { event => 'in_test_timed', cb_data => 'testing' };
        note('in_test_timed');
        sleep 1;
        return 'xyzzy';
    }

    sub _test_logger {
        my ($event, $data, $cb_data) = @_;
        push @events, { event => $event, data => $data, cb_data => $cb_data };
        note($event, ' : ', $data);
        return;
    }
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
