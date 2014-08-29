#!/usr/bin/env perl

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
