=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### Bio::Otter::LogFile

package Bio::Otter::LogFile;

use strict;
use warnings;
use Carp;

use POSIX ();
use IO::Handle;
use Bio::Otter::Log::Log4perl qw(:levels);
use Try::Tiny;

use Bio::Otter::Log::TieHandle;

my $logfile;

sub make_log {
    my ($file, $level, $config) = @_;
    confess "Already logging to '$logfile'" if $logfile;
    $logfile = $file;

    my $default_conf = qq(
      log4perl.rootLogger = $level, SafeScreen, Logfile

      log4perl.appender.SafeScreen                          = Bio::Otter::Log::Appender::SafeScreen
      log4perl.appender.SafeScreen.layout                   = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.SafeScreen.layout.ConversionPattern = %m%n

      log4perl.appender.Logfile                          = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename                 = $logfile
      log4perl.appender.Logfile.layout                   = Bio::Otter::Log::Layout::UseSrcTimestamp
      log4perl.appender.Logfile.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss,SSSS} %c [%X{name}] %p: %m%n
      log4perl.appender.Logfile.layout.Debug             = 0

      # used by Bio::Otter::Client->_debug_client, defaults to fatal-only
      log4perl.logger.otter.client     = FATAL, SafeScreen, Logfile
      log4perl.additivity.otter.client = 0

      # quench screen output of test output
      log4perl.logger.Test.LogFile = TRACE, Logfile
      log4perl.additivity.Test.LogFile = 0
    );

    $config ||= \$default_conf;
    # TODO: Use Log::Log4perl::Config::PropertyConfigurator here, then set filename as necessary.
    Log::Log4perl::MDC->put('name' => '-'); # default for %X{name}, set by B:O:Log::WithContext->get_logger().
    Log::Log4perl->init($config);

    my $logger = Bio::Otter::Log::Log4perl->get_logger;
    $logger->info('In parent, pid ', $$);

    # Unbuffer STDOUT
    STDOUT->autoflush(1);

    if (my $pid = open(STDOUT, "|-")) {
        # Send parent's STDERR to the same place as STDOUT, for subprocesses.
        open STDERR, '>&', \*STDOUT or confess "Can't redirect STDERR to STDOUT";

        # Now for us in perl land, tie STDERR and STDOUT to Log4perl.

        tie *STDERR, 'Bio::Otter::Log::TieHandle',
            level => $WARN, category => "otter.stderr", orig => \*STDERR
              or die "tie failed ($!)";

        tie *STDOUT, 'Bio::Otter::Log::TieHandle',
            level => $INFO, category => "otter.stdout", orig => \*STDOUT
              or die "tie failed ($!)";

        return $pid; ### Could write a rotate_logfile sub if we record the pid.

    } elsif (defined $pid) {

        $logger->info('In child, pid ', $$);
        $0 .= ":logger";

        # ensure logs are written when app is zapped / GUI zaps kids
        $SIG{TERM} = 'IGNORE';
        $SIG{INT} = sub {
            $logger->info("Logger ignored SIGINT");
            # then most likely, "Logger stdin sysread: Interrupted system call"
            return;
        };

        my $child_logger = Bio::Otter::Log::Log4perl->get_logger('otter.children');

        my $maxline = 4096; # RT#422965 limit unbroken line length
        my $buff = '';
        my $flush = sub {
            if ($buff ne '') {
                $logger->warn("flushing unterminated log text");
                $child_logger->warn($buff);
                $buff = '';
            }
            return;
        };
        while(1) {
            my $n = STDIN->sysread($buff, $maxline + 512, length($buff));
            # sysread rather than read, so that we promptly get whole
            # lines before reaching $maxline
            if (!defined $n) {
                # error
                $logger->error("Logger stdin sysread: $!");
                STDIN->clearerr;
                $flush->();
            } elsif ($n) {
                # data
                while ($buff =~ s{\A(?:(.{0,$maxline})\n|(.{$maxline}))}{}) {
                    my $txt = defined $1 ? $1 : $2;
                    # take whole lines, or a big bite off the front of
                    # an unbroken line
                    $child_logger->warn($txt);
                }
                # there may be some $buff left
            } else {
                # EOF is often preceded by an (ignored) SIGTERM from the GUI
                $flush->();
                $logger->info("Logger EOF");
                last;
            }
        };

        # close the output file & screen writer.  _exit does not flush.
        Log::Log4perl->eradicate_appender('Logfile');
        Log::Log4perl->eradicate_appender('SafeScreen');

        # Child must exit here.  Do not called outstanding DESTROY
        # methods (there should be none, but don't assume that)
        POSIX::_exit(0);

    } else {
        confess "Can't fork output filter: $!";
    }

    return (); # not reached
}

sub unmake_log {
    my ($called) = @_;

    # For use during global destruction, so "warn" will work properly
    # instead of making Log4perl complain about lack of init
    try {
        Bio::Otter::Log::TieHandle->untie_for(*STDOUT);
    } catch {
        warn "Untie STDOUT: $_";
    };
    try {
        Bio::Otter::Log::TieHandle->untie_for(*STDERR);
    } catch {
        warn "Untie STDERR: $_";
    };

    return;
}

sub current_logfile {
    return $logfile;
}

1;

__END__

=head1 NAME - Bio::Otter::LogFile

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

