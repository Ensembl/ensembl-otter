package Bio::Otter::DBSQL::CloneLockAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::DBSQL::AuthorAdaptor;
use Bio::Otter::CloneLock;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

sub _generic_sql_fetch {
    my( $self, $where_clause, @param ) = @_;

    my $sth = $self->prepare(q{
        SELECT clone_lock_id
          , clone_id
          , author_id
          , UNIX_TIMESTAMP(timestamp)
        FROM clone_lock
        } . $where_clause);
    $sth->execute(@param);

    my $aad = $self->db->get_AuthorAdaptor;

    my( @clonelock );
    while (my $row = $sth->fetch) {
        my $author = $aad->fetch_by_dbID($row->[2]);

        my $clonelock = new Bio::Otter::CloneLock(
            -DBID      => $row->[0],
            -CLONE_ID  => $row->[1],
            -AUTHOR    => $author,
            -TIMESTAMP => $row->[3],
            );

        push(@clonelock, $clonelock);
    }
    return @clonelock;
}

sub fetch_by_dbID {
    my( $self, $id ) = @_;
    
    if (!defined($id)) {
	$self->throw("Id must be entered to fetch a CloneLock object");
    }
    
    my ($obj) = $self->_generic_sql_fetch("where clone_lock_id = ? ", $id);

    return $obj;
}

sub fetch_by_clone_id {
    my( $self, $id ) = @_;

    $self->throw("Clone id must be entered to fetch a CloneLock object")
        unless $id;
    
    my ($obj) = $self->_generic_sql_fetch("where clone_id = ? ", $id);

    return $obj;
}


sub list_by_author {
    my( $self, $auth ) = @_;

    $self->throw("Author must be entered to fetch a CloneLock object")
        unless $auth;
    
    my @locks = $self->_generic_sql_fetch("where author_id = ? ", $auth->dbID);

    return @locks;
}


sub store {
    my( $self, $clone_lock ) = @_;

    $self->throw("Must provide a CloneLock object to the store method")
        unless $clone_lock;
    $self->throw("Argument must be a CloneLock object to the store method.  Currently is [$clone_lock]")
        unless $clone_lock->isa("Bio::Otter::CloneLock");

    my $clone_id = $clone_lock->clone_id or $self->throw('clone_id not set on CloneLock object');
    my $author   = $clone_lock->author   or $self->throw(  'author not set on CloneLock object');

    my $author_id = $author->dbID;
    unless ($author_id) {
        my $authad = $self->db->get_AuthorAdaptor;
        $authad->store($author);
        $author_id = $author->dbID;
    }

    my $authad = new Bio::Otter::DBSQL::AuthorAdaptor($self->db); 
    $authad->store($clone_lock->author); 

    my $sth = $self->prepare(q{
        INSERT INTO clone_lock( clone_lock_id
              , clone_id
              , author_id
              , timestamp)
        VALUES (NULL, ?, ?, NOW())
        });
    $sth->execute($clone_id, $author_id);

    my $clone_lock_id = $sth->{'mysql_insertid'}
        or $self->throw('Failed to get new autoincremented ID for lock');
    $clone_lock->dbID($clone_lock_id);
}

sub remove {
    my( $self, $clone_lock ) = @_;

    $self->throw("Must provide a CloneLock to the remove method")
        unless $clone_lock;
    my $clone_id = $clone_lock->clone_id
        or $self->throw('clone_id not set on CloneLock object');

    my $sth = $self->prepare("DELETE FROM clone_lock WHERE clone_id = ?");
    $sth->execute($clone_id);
    $self->throw("Failed to remove CloneLock for clone " . $clone_id) unless $sth->rows;
}



1;

	





