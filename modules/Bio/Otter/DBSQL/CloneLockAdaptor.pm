package Bio::Otter::DBSQL::CloneLockAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::DBSQL::AuthorAdaptor;
use Bio::Otter::CloneLock;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

=head2 _generic_sql_fetch

 Title   : _generic_sql_fetch
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub _generic_sql_fetch {
	my( $self, $where_clause ) = @_;

	my $sql = q{
		SELECT clone_lock_id,
                       clone_id,
                       clone_version,
                       author_id,
                       timestamp
		FROM clone_lock }
	. $where_clause;


	my $sth = $self->prepare($sql);
	$sth->execute;

	my $aad = new Bio::Otter::DBSQL::AuthorAdaptor($self->db);

	my @clonelock;

	while (my $ref = $sth->fetchrow_hashref) {
	    my $lock_id   = $ref->{clone_lock_id};
	    my $clone_id  = $ref->{clone_id};
            my $version   = $ref->{clone_version};
	    my $author_id = $ref->{author_id};
	    my $timestamp = $ref->{timestamp};

	    my $author = $aad->fetch_by_dbID($author_id);
	    
	    my $clonelock = new Bio::Otter::CloneLock(-dbId      => $lock_id,
						      -id        => $clone_id,
                                                      -version   => $version,
						      -author    => $author,
						      -timestamp => $timestamp
						      );

	    push(@clonelock,$clonelock);

	    
	}

	return @clonelock;
    }

=head2 fetch_by_dbID

 Title   : fetch_by_dbID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_dbID {
    my ($self,$id) = @_;
    
    if (!defined($id)) {
	$self->throw("Id must be entered to fetch a CloneLock object");
    }
    
    my ($obj) = $self->_generic_sql_fetch("where clone_lock_id = $id");

    return $obj;
}

=head2 fetch_by_clone_id

 Title   : fetch_by_clone_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_clone_id{
   my ($self,$id) = @_;

    if (!defined($id)) {
	$self->throw("Clone id must be entered to fetch a CloneLock object");
    }
    
    my @obj = $self->_generic_sql_fetch("where clone_id = \'$id\'");

   return @obj;
}


sub fetch_by_clone_id_version{
   my ($self,$id,$version) = @_;

    if (!defined($id)) {
	$self->throw("Clone id must be entered to fetch a CloneLock object");
    }
    if (!defined($version)) {
	$self->throw("Clone version must be entered to fetch a CloneLock object");
    }
    
    my ($obj) = $self->_generic_sql_fetch("where clone_id = \'$id\' and clone_version = $version");

   return $obj;
}

=head2 list_by_author

 Title   : list_by_author
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub list_by_author{
    my ($self,$auth) = @_;

    if (!defined($auth)) {
	$self->throw("Author must be entered to fetch a CloneLock object");
    }
    
    my @locks = $self->_generic_sql_fetch("where author_id = ". $auth->dbID);

    return @locks;
    

}


sub store {
  my ($self,$clonelock) = @_;

  if (!defined($clonelock)) {
     $self->throw("Must provide a CloneLock object to the store method");
 } elsif (! $clonelock->isa("Bio::Otter::CloneLock")) {
     $self->throw("Argument must be a CloneLock object to the store method.  Currently is [$clonelock");
  }

  my $authad = new Bio::Otter::DBSQL::AuthorAdaptor($self->db); 
  $authad->store($clonelock->author); 
  
  my $sql = "insert into clone_lock(clone_lock_id,clone_id,clone_version,author_id,timestamp) values (null,\'" . 
      $clonelock->id . "\'," . $clonelock->version . "," . 
      $clonelock->author->dbID . ",now())";

  #print $sql . "\n";

  my $sth = $self->prepare($sql);
  my $rv = $sth->execute();
  
  $self->throw("Failed to insert CloneLock for clone " . $clonelock->clone_id) unless $rv;
  
  $sth = $self->prepare("select last_insert_id()");
  my $res = $sth->execute;
  my $row = $sth->fetchrow_hashref;
  $sth->finish;
  
  $clonelock->dbID($row->{'last_insert_id()'});
}

=head2 remove

 Title   : remove
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub remove_by_clone_id_version {
   my ($self,$cloneid,$version) = @_;

   if (!defined($cloneid)) {
       $self->throw("Must provide a clone id to the remove method");
   }
   if (!defined($version)) {
       $self->throw("Must provide a version to the remove method");
   }
  
   my $sql = "delete from clone_lock where clone_id = \'$cloneid\' and clone_version = $version";

   my $sth = $self->prepare($sql);
   my $rv = $sth->execute();
   
   $self->throw("Failed to remove CloneLock for clone " . $cloneid) unless $rv;
}



1;

	





