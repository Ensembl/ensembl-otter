package Bio::Otter::Lock;

# clone info file

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$id,$version,$author,$timestamp,$type)  = 
      $self->_rearrange([qw(DBID ID AUTHOR TIMESTAMP TYPE
                            )],@args);

  $self->dbID($dbid);
  $self->id($id);
  $self->version($version);
  $self->author($author);
  $self->timestamp($timestamp);
  $self->type($type);

  return $self;
}

sub dbID{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}

sub id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'id'} = $value;
    }
    return $obj->{'id'};

}

sub author{
   my ($self,$value) = @_;

   if( defined $value) {
		 if ($value->isa("Bio::Otter::Author")) {
			 $self->{'author'} = $value;
		 } else {
			 $self->throw("Argument [$value] is not a Bio::Otter::Author");
		 }
	 }
    return $self->{'author'};
}

sub timestamp{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'timestamp'} = $value;
    }
    return $obj->{'timestamp'};

}

sub type {
  my ($obj,$value) = @_;
  
  if (defined($value)) {
    $obj->{_type} = $value;
  }
  return $obj->{_type};
}

1;


