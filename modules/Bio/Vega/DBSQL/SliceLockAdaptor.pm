package Bio::Vega::DBSQL::SliceLockAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Vega::DBSQL::AuthorAdaptor;
use Bio::Vega::SliceLock;
use base qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);


sub _generic_sql_fetch {
  my ($self, $where_clause, @param) = @_;
  my $sth = $self->prepare(q{
        SELECT slice_lock_id
          , seq_region_id
          , author_id
          , UNIX_TIMESTAMP(timestamp)
          , hostname
        FROM slice_lock
        } . $where_clause);
  $sth->execute(@param);

  my $aad = $self->db->get_AuthorAdaptor;
  my $slicelocks=[];
  while (my $row = $sth->fetch) {

      my $author = $aad->fetch_by_dbID($row->[2]);
      my $slicelock = Bio::Vega::SliceLock->new(
          -DBID       => $row->[0],
          -SLICE_ID  => $row->[1],
          -AUTHOR     => $author,
          -TIMESTAMP  => $row->[3],
          -HOSTNAME   => $row->[4],
          );
      push(@$slicelocks, $slicelock);

  }
  return $slicelocks;
}

sub fetch_by_dbID {
  my ($self, $id) = @_;
  if (!defined($id)) {
      throw("Id must be entered to fetch a SliceLock object");
  }
  my ($obj) = $self->_generic_sql_fetch("where slice_lock_id = ? ", $id);
  return $obj->[0];
}

sub fetch_by_slice_id {
  my ($self, $id) = @_;
  throw("Slice seq_region_id must be entered to fetch a SliceLock object")
      unless $id;
  my ($obj) = $self->_generic_sql_fetch("where seq_region_id = ? ", $id);
  return $obj->[0];
}


sub list_by_author {
  my ($self, $auth) = @_;
  throw("Author must be entered to fetch a SliceLock object")
      unless $auth;
  my $slicelocks = $self->_generic_sql_fetch("where author_id = ? ", $auth->dbID);
  return $slicelocks;
}


sub store {
  my ($self, $slice_lock) = @_;
  throw("Must provide a SliceLock object to the store method")
      unless $slice_lock;
  throw("Argument must be a SliceLock object to the store method.  Currently is [$slice_lock]")
      unless $slice_lock->isa("Bio::Vega::SliceLock");
  my $slice_id = $slice_lock->slice_id or $self->throw('slice_id not set on SliceLock object');
  my $author   = $slice_lock->author   or $self->throw(  'author not set on SliceLock object');
  my $author_id = $author->dbID;
  unless ($author_id) {
      my $authad = $self->db->get_AuthorAdaptor;
      $authad->store($author);
      $author_id = $author->dbID;
  }
  my $authad = Bio::Vega::DBSQL::AuthorAdaptor->new($self->db);
  $authad->store($slice_lock->author);
  my $sth = $self->prepare(q{
        INSERT INTO slice_lock( slice_lock_id
              , seq_region_id
              , author_id
              , timestamp
              , hostname)
        VALUES (NULL, ?, ?, NOW(), ?)
        });
  $sth->execute($slice_id, $author_id, $slice_lock->hostname);
  my $slice_lock_id = $sth->{'mysql_insertid'}
  or throw('Failed to get new autoincremented ID for lock');
  $slice_lock->dbID($slice_lock_id);

  return;
}

sub remove {
  my ($self, $slice_lock) = @_;
  $self->throw("Must provide a SliceLock to the remove method")
      unless $slice_lock;
  my $slice_id = $slice_lock->slice_id
      or $self->throw('slice_id not set on SliceLock object');
  my $sth = $self->prepare("DELETE FROM slice_lock WHERE seq_region_id = ?");
  $sth->execute($slice_id);
  $self->throw("Failed to remove SliceLock for slice " . $slice_id) unless $sth->rows;
  return;
}

1;
