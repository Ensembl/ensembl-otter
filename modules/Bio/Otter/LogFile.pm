
### Bio::Otter::LogFile

package Bio::Otter::LogFile;

use strict;
use warnings;
use Carp;
use IO::Handle;

my $file;
sub make_log {
    confess "Already logging to '$file'" if $file;
    
    $file = shift;

    # Unbuffer STDOUT
    STDOUT->autoflush(1);

    if (my $pid = open(STDOUT, "|-")) {
        # Send parent's STDERR to the same place as STDOUT.
        open STDERR, '>&', \*STDOUT or confess "Can't redirect STDERR to STDOUT";
        return $pid; ### Could write a rotate_logfile sub if we record the pid.
    }
    elsif (defined $pid) {
        open my $log, '>>', $file or confess "Can't append to logfile '$file': $!";
        
        # Unbuffer logfile
        $log->autoflush(1);

        # Parent will try to kill us if it finishes cleanly, but we
        # may need to wait and write out the final logs.
        $SIG{'TERM'} = 'IGNORE'; ## no critic (Variables::RequireLocalizedPunctuationVars)

        # Child filters output from parent
        while (<STDIN>) { ## no critic(InputOutput::ProhibitExplicitStdin)
            print STDERR $_;    # Still print to STDERR
            printf $log "%s  %s", scalar(localtime), $_;
        }
        close $log;
        exit;   # Child must exit here!
    }
    else {
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

