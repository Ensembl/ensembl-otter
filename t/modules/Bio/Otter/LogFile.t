#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

use File::Slurp;
use File::Temp;
use FindBin qw($Script);
use Time::HiRes qw( gettimeofday tv_interval );

use Log::Log4perl;

my @modules;
BEGIN {
    @modules = qw(
       Bio::Otter::LogFile
       Bio::Otter::Log::Appender::SafeScreen
       Bio::Otter::Log::Layout::UseSrcTimestamp
       Bio::Otter::Log::TieHandle
    );

    use_ok($_) foreach (@modules);
}
critic_module_ok($_) foreach (@modules);

my $fh = File::Temp->new(TEMPLATE => "${Script}.XXXXXX", TMPDIR => 1);
my $fname = $fh->filename;

my $pid = Bio::Otter::LogFile::make_log($fname, 'DEBUG');
ok($pid, 'make_log');

my $logger = Log::Log4perl->get_logger('LogFileT');
isa_ok($logger, 'Log::Log4perl::Logger');

ok($logger->info('Stand by for an information broadcast'), 'info');

my $n = 1000;
my $t0 = [ gettimeofday() ];
foreach my $i ( 1 .. $n ) {
    $logger->debug("Debug message #$i");
}
my $interval = tv_interval($t0);

my $log = read_file($fh);
ok($log, 'slurp logfile');

like($log, qr/LogFileT INFO: Stand by for an information broadcast/, 'info logged');

note "Logged $n messages in $interval seconds.";

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
