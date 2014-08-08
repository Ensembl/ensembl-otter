#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::TimeDiff';
    use_ok($module, 'time_diff_for');
}
critic_module_ok($module);

do {
    local $SIG{__WARN__} = sub { note(@_) };
    time_diff_for( sub { sleep 1; } );
    ok('defaults');
};

{
    my @events;

    my $diff = time_diff_for(\&_test_timed, \&_test_logger, 'testing');

    is(scalar(@events), 4, 'n_events');
    ok($diff, 'have retval');
    is_deeply([map { $_->{event} }   @events], [qw( start in_test_timed end elapsed )], 'events');
    is_deeply([map { $_->{cb_data} } @events], [qw( testing ) x 4 ],                    'cb_data');
    is($diff, $events[-1]{data}, 'elapsed via logger');

    sub _test_timed {
        push @events, { event => 'in_test_timed', cb_data => 'testing' };
        note('in_test_timed');
        sleep 1;
        return;
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
