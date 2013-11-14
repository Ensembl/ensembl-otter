package Bio::Otter::Utils::RipVanWinkle;
use strict;
use warnings;
use Time::HiRes qw( tv_interval gettimeofday );
use Try::Tiny;


=head1 NAME

Bio::Otter::Utils::RipVanWinkle - notice when we wake up late

=head1 DESCRIPTION

Request regular ticks.  Log the ones that arrive very late.

=cut


sub new {
    my ($pkg, $main_window, $millis, $overdue_factor) = @_;

    my $self = { widg => $main_window,
                 every => $millis,
                 factor => $overdue_factor };
    bless $self, $pkg;
    $$self{timer} = $main_window->repeat($millis, [ $self, 'tick' ]);

    return $self;
}

{
    my $have_loadavg;
    sub _init {
        $have_loadavg = try { require Sys::LoadAvg };
        return;
    }

    sub __load_info {
        return 'load(unknown)' unless $have_loadavg;
        my @load = Sys::LoadAvg::loadavg();
        return "load(@load)";
    }
}

sub tick {
    my ($self) = @_;

    my @last_wall = @{ $$self{wall} || [] };
    @{ $$self{wall} } = gettimeofday();

    my $last_cpu = $$self{cpu};
    my @T = times();
    ($$self{cpu}) = $T[0] + $T[1]; # user+system CPU time, seconds to 2dp

    if (@last_wall) {
        # working in seconds
        my $want = $$self{every} / 1000;
        my $max_factor = $$self{factor};
        my $got = tv_interval(\@last_wall, $$self{wall});

        if ($got > $want * $max_factor) {
            my $cpu_used = $$self{cpu} - $last_cpu;
            warn sprintf("RvW: woke late.  %.2fs late on %.2fs tick (%.1fx); used %.2f CPUsec (%.1f%%); %s\n",
                         $got - $want, $want, $got / $want,
                         $cpu_used, 100 * $cpu_used / $got,
                         __load_info());
        }
    }
    return;
}


sub stop {
    my ($self) = @_;
    my $timer = delete $$self{timer};
    $timer->cancel if $timer;
    return;
}

sub DESTROY {
    my ($self) = @_;
    $self->stop;
    return;
}


__PACKAGE__->_init;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
