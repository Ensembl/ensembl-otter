
package Bio::Otter::CloneLock;

### Maybe simpler for each Lock to have-a Clone and an Author
### (instead of a clone_id)?

use strict;
use Bio::EnsEMBL::Root;
use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid, $clone_id, $author, $timestamp, $hostname)  = 
      $self->_rearrange([qw(DBID CLONE_ID AUTHOR TIMESTAMP HOSTNAME
                            )],@args);

  $self->dbID($dbid);
  $self->clone_id($clone_id);
  $self->author($author);
  $self->timestamp($timestamp);
  $self->hostname($hostname);

  return $self;
}

sub dbID{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}

sub clone_id {
    my( $self, $clone_id ) = @_;
    
    if ($clone_id) {
        $self->{'_clone_id'} = $clone_id;
    }
    return $self->{'_clone_id'};
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

sub hostname {
    my( $self, $hostname ) = @_;
    
    if ($hostname) {
        $self->{'_hostname'} = $hostname;
    }
    return $self->{'_hostname'};
}



1;


