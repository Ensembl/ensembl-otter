
### Bio::Otter::LogFile

package Bio::Otter::LogFile;

use strict;
use Symbol 'gensym';
use Carp;

sub import {
    my $class = shift;

    $class->make_log(@_) if @_;
}

my $prefix_sub = sub {
    return scalar(localtime) . " - ";
    };

sub set_prefix_sub {
    $prefix_sub = shift;
}

sub make_log {
    my( $class, $file ) = @_;

    # Unbuffer STDOUT
    my $oldsel = select(STDOUT);
    $| = 1;
    select($oldsel);

    if (my $pid = open(STDOUT, "|-")) {
        # Send parent's STDERR to the same place as STDOUT.
        open STDERR, ">&STDOUT" or confess "Can't redirect STDERR to STDOUT";
        return $pid;
    }
    elsif (defined $pid) {
        my $log = gensym();
        open $log, "> $file" or confess "Can't write to logfile '$file': $!";
        
        # Unbuffer logfile
        $oldsel = select($log);
        $| = 1;
        select($oldsel);
        
        # Child filters output from parent
        while (<STDIN>) {
            print STDERR $_;    # Still print to STDERR
            print $log $prefix_sub->(), $_;
        }
        close $log;
        exit;   # Child must exit here!
    }
    else {
        confess "Can't fork STDOUT filter: $!";
    }
}

1;

__END__

=head1 NAME - Bio::Otter::LogFile

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

