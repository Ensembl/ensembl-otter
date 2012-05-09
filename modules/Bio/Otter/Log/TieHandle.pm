package Bio::Otter::Log::TieHandle;

use strict;
use warnings;

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
    unless ($self->{called}) {
        local $self->{called} = 1; # avoid recursion - thanks to Tie::Log4perl
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

__END__

=head1 NAME - Bio::Otter::Log::TieHandle

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
