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
      $self->_rearrange([qw(DBID ID VERSION AUTHOR TIMESTAMP TYPE
                            )],@args);

  $self->dbID($dbid);
  $self->id($id);
  $self->version($version);
  $self->author($author);
  $self->timestamp($timestamp);
  $self->type($type);

  return $self;
}

=head2 dbID

 Title   : dbID
 Usage   : $obj->dbID($newval)
 Function: 
 Example : 
 Returns : value of dbID
 Args    : newvalue (optional)


=cut

sub dbID{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}

=head2 id

 Title   : id
 Usage   : $obj->id($newval)
 Function: 
 Example : 
 Returns : value of id
 Args    : newvalue (optional)


=cut

sub id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'id'} = $value;
    }
    return $obj->{'id'};

}


=head2 author

 Title   : author
 Usage   : $obj->author($newval)
 Function: 
 Example : 
 Returns : value of author
 Args    : newvalue (optional)


=cut

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

=head2 timestamp

 Title   : timestamp
 Usage   : $obj->timestamp($newval)
 Function: 
 Example : 
 Returns : value of timestamp
 Args    : newvalue (optional)


=cut

sub timestamp{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'timestamp'} = $value;
    }
    return $obj->{'timestamp'};

}

sub version {
  my ($obj,$value) = @_;
  
  if (defined($value)) {
    $obj->{_version} = $value;
  }
  return $obj->{_version};
}

sub type {
  my ($obj,$value) = @_;
  
  if (defined($value)) {
    $obj->{_type} = $value;
  }
  return $obj->{_type};
}
1;


