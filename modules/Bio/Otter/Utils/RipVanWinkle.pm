=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
    my $have_cpuload;
    my $have_loadavg;
    sub _init {
        $have_cpuload = try { require Sys::CpuLoad };
        return if $have_cpuload;
        $have_loadavg = try { require Sys::LoadAvg };
        return;
    }

    sub __load_info {
        if ($have_cpuload) {
            my @load = Sys::CpuLoad::load();
            return "load(@load)";
        }
        if ($have_loadavg) {
            my @load = Sys::LoadAvg::loadavg();
            return "load(@load)";
        }
        return 'load(unknown)';
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
