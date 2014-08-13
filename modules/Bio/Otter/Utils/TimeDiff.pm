package Bio::Otter::Utils::TimeDiff;

# report on the time taken by a function

use strict;
use warnings;

use Time::HiRes qw( time gettimeofday );

use base qw( Exporter );
our @EXPORT_OK = qw( time_diff_for );

# Not a method!
#
sub time_diff_for {
    my ($timed_code, $log_cb, $log_cb_data) = @_;

    $log_cb      ||= \&_default_logger;
    $log_cb_data ||= "$timed_code";

    _log_timestamp('start', $log_cb, $log_cb_data);

    my $start_time = time;
    my @retval = $timed_code->();
    my $end_time = time;

    _log_timestamp('end', $log_cb, $log_cb_data);

    my $time = sprintf "%.3f", $end_time - $start_time;
    $log_cb->('elapsed', $time, $log_cb_data);

    return wantarray ? @retval : $retval[0];
}

# Also a template for callers:
#
sub _default_logger {
    my ($event, $data, $cb_data) = @_;
    warn sprintf "%s %-7s : %s\n", $cb_data, $event, $data;
    return;
}

sub _log_timestamp {
    my ($event, $log_cb, $log_cb_data) = @_;

    my ($sec, $micro) = gettimeofday();
    my @t = localtime($sec);
    my @date = ( 1900+$t[5], $t[4]+1, @t[3,2,1,0] );

    my $data = sprintf "%4d-%02d-%02d %02d:%02d:%02d,%04.0f", @date, $micro / 100;
     $log_cb->($event, $data, $log_cb_data);

    return;
}

1;
