
### Bio::Otter::LogFile

package Bio::Otter::LogFile;

use strict;
use warnings;
use Carp;

use Log::Log4perl qw(:levels);

use Bio::Otter::Log::TieHandle;

my $file;

sub make_log {
    confess "Already logging to '$file'" if $file;
    my ($config, $level);
    ($file, $level, $config) = @_;

    my $default_conf = qq(
      log4perl.rootLogger = $level, SafeScreen, Logfile

      log4perl.appender.SafeScreen                          = Bio::Otter::Log::Appender::SafeScreen
      log4perl.appender.SafeScreen.layout                   = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.SafeScreen.layout.ConversionPattern = %m%n

      log4perl.appender.Logfile                          = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename                 = $file
      log4perl.appender.Logfile.layout                   = Log::Log4perl::Layout::PatternLayout::Multiline
      log4perl.appender.Logfile.layout.ConversionPattern = %d %c %p: %m%n
    );

    $config ||= \$default_conf;
    # TODO: Use Log::Log4perl::Config::PropertyConfigurator here, then set filename as necessary.
    Log::Log4perl->init($config);

    my $logger = Log::Log4perl->get_logger;
    $logger->info('In parent, pid ', $$);

    # Unbuffer STDOUT
    STDOUT->autoflush(1);

    if (my $pid = open(STDOUT, "|-")) {

        # Send parent's STDERR to the same place as STDOUT, for subprocesses.
        open STDERR, '>&', \*STDOUT or confess "Can't redirect STDERR to STDOUT";

        # Now for us in perl land, tie STDERR and STDOUT to Log4perl.

        tie *STDERR, 'Bio::Otter::Log::TieHandle',
            level => $WARN, category => "otter.stderr" or die "tie failed ($!)";

        tie *STDOUT, 'Bio::Otter::Log::TieHandle',
            level => $INFO, category => "otter.stdout" or die "tie failed ($!)";

        return $pid; ### Could write a rotate_logfile sub if we record the pid.

    } elsif (defined $pid) {

        $logger->info('In child, pid ', $$);

        my $child_logger = Log::Log4perl->get_logger('otter.children');

        while (<STDIN>) { ## no critic(InputOutput::ProhibitExplicitStdin)
            chomp;
            $child_logger->warn($_);
        }

        exit;   # Child must exit here!

    } else {
        confess "Can't fork output filter: $!";
    }
}

sub current_logfile {
    return $file;
}

1;

__END__

=head1 NAME - Bio::Otter::LogFile

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

