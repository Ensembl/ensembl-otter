package Bio::Otter::CloneLock;

# clone info file

use vars qw(@ISA);
use strict;

use Bio::Otter::Lock;

@ISA = qw(Bio::Otter::Lock);

sub new {
  my($class,@args) = @_;

  my $self = $class->SUPER::new(@args);


  bless $self,$class;
  
  return $self;
}

sub type {
  my ($self,$arg) = @_;

  if (defined($arg)) {
    $self->throw("Can't set type to [$arg] on CloneLock - is always CLONE")
  }
 
  return "CLONE";
}
1;


