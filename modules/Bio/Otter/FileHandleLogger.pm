package Bio::Otter::FileHandleLogger;

use strict;
use warnings;

open(my $realstdout, ">&STDOUT") or die "Can't dup STDOUT";

use Log::Log4perl qw(:levels get_logger);
 
sub TIEHANDLE {
   my($class, %options) = @_;
 
   my $self = {
       level    => $DEBUG,
       category => '',
       %options
   };
 
   $self->{logger} = get_logger($self->{category});
   bless $self, $class;
   return $self;
}
 
sub PRINT {
    my($self, @rest) = @_;
    if ($Log::Log4perl::caller_depth) { # avoid recursion
        print $realstdout @rest;
    } else {
        $Log::Log4perl::caller_depth++;
        $self->{logger}->log($self->{level}, @rest);
        $Log::Log4perl::caller_depth--;
    }
    return;
}
 
sub PRINTF {
    my($self, $fmt, @rest) = @_;
    $Log::Log4perl::caller_depth++;
    $self->PRINT(sprintf($fmt, @rest));
    $Log::Log4perl::caller_depth--;
    return;
}
 
1;
