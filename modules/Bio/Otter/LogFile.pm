
### Bio::Otter::LogFile

package Bio::Otter::LogFile;

use strict;
{
    # On perl 5.8.0 this check generates the warning:
    # 'v-string in use/require non-portable'
    no warnings;
    # tie doesn't work properly for filehandles
    # on earlier versions of perl:
    use v5.8.0;  
}
use Symbol 'gensym';

my $log;    # Variable stores logging filehandle

my $prefix_sub = sub {
    return scalar(localtime) . " - ";
    };

sub import {
    my $class = shift;

    $class->make_log(@_) if @_;
}

sub make_log {
    my( $class, $file ) = @_;
    
    if ($log) {
        print_to_log("Switching log to '$file'");
        close($log);
        untie *STDERR;
        untie *STDOUT;
    }
    
    # Create logging filehandle
    $log = gensym();
    open($log, '>', $file)
        or die "Can't write log to '$file' : $!";

    # Unbuffer our logging filehandle
    my $oldfh = select($log);
    $| = 1;
    select($oldfh);

    tie *STDERR, $class;
    tie *STDOUT, $class;
}

sub set_prefix_sub {
    $prefix_sub = shift;
}

sub TIEHANDLE {
    return bless {}, shift;
}

sub PRINT {
    shift;  # Don't need $self
    
    print_to_log(@_);
}

sub PRINTF {
    shift;  # Don't need $self
    my $fmt = shift;
    
    print_to_log(sprintf($fmt, @_));
}

sub print_to_log {
    
    print $log $prefix_sub->(), @_;
    
    # Add an extra newline for a neat message
    print $log "\n" unless $_[$#_] =~ /\n$/;
}


1;

__END__

=head1 NAME - Bio::Otter::LogFile

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

