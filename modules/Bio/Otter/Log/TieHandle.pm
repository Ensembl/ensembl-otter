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

package Bio::Otter::Log::TieHandle;

use strict;
use warnings;

use Bio::Otter::Log::Log4perl qw(:levels get_logger);

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

# "close STDERR" is a standard child-shutdown idiom.
# When STDERR is tied, that call comes here and the real STDERR
# remains open, so untie and then do a real close.
sub CLOSE {
    my ($self, @arg) = @_;

#    warn "CLOSE for @{[ %$self ]}\n";

    my $fh = $self->{orig};
    undef $self; # should be the last reference to it
    untie *$fh;

    die "recursive close because untie failed" # for safety
      if defined caller(500); # arbitrary limit

    return close($fh);
}

sub untie_for {
    my ($pkg, $tied_fh) = @_;

    # untie is tricky, need to drop every other reference to $self
    # first.  Do it this way so caller is not holding a ref
    my $self = tied($tied_fh);

    if (my $fh = $self->{orig}) {
        undef $self;
        untie *$fh;
    }

    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Log::TieHandle

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
