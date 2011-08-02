package Bio::Vega::DBSQL::ContigLockAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Vega::DBSQL::AuthorAdaptor;
use Bio::Vega::ContigLock;
use base qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);


sub _generic_sql_fetch {
  my( $self, $where_clause, @param ) = @_;
  my $sth = $self->prepare(q{
        SELECT contig_lock_id
          , seq_region_id
          , author_id
          , UNIX_TIMESTAMP(timestamp)
          , hostname
        FROM contig_lock
        } . $where_clause);
  $sth->execute(@param);

  my $aad = $self->db->get_AuthorAdaptor;
  my $contiglocks=[];
  while (my $row = $sth->fetch) {

      my $author = $aad->fetch_by_dbID($row->[2]);
      my $contiglock = Bio::Vega::ContigLock->new(
          -DBID       => $row->[0],
          -CONTIG_ID  => $row->[1],
          -AUTHOR     => $author,
          -TIMESTAMP  => $row->[3],
          -HOSTNAME   => $row->[4],
          );
      push(@$contiglocks, $contiglock);

  }
  return $contiglocks;
}

sub fetch_by_dbID {
  my( $self, $id ) = @_;
  if (!defined($id)) {
      throw("Id must be entered to fetch a ContigLock object");
  }
  my ($obj) = $self->_generic_sql_fetch("where contig_lock_id = ? ", $id);
  return $obj->[0];
}

sub fetch_by_contig_id {
  my( $self, $id ) = @_;
  throw("Contig seq_region_id must be entered to fetch a ContigLock object")
      unless $id;
  my ($obj) = $self->_generic_sql_fetch("where seq_region_id = ? ", $id);
  return $obj->[0];
}


sub list_by_author {
  my( $self, $auth ) = @_;
  throw("Author must be entered to fetch a ContigLock object")
      unless $auth;
  my $locks = $self->_generic_sql_fetch("where author_id = ? ", $auth->dbID);
  return $locks;
}


sub store {
  my( $self, $contig_lock ) = @_;
  throw("Must provide a ContigLock object to the store method")
      unless $contig_lock;
  throw("Argument must be a ContigLock object to the store method.  Currently is [$contig_lock]")
      unless $contig_lock->isa("Bio::Vega::ContigLock");
  my $contig_id = $contig_lock->contig_id or $self->throw('contig_id not set on ContigLock object');
  my $author   = $contig_lock->author   or $self->throw(  'author not set on ContigLock object');
  my $author_id = $author->dbID;
  unless ($author_id) {
      my $authad = $self->db->get_AuthorAdaptor;
      $authad->store($author);
      $author_id = $author->dbID;
  }
  my $authad = Bio::Vega::DBSQL::AuthorAdaptor->new($self->db);
  $authad->store($contig_lock->author);
  my $sth = $self->prepare(q{
        INSERT INTO contig_lock( contig_lock_id
              , seq_region_id
              , author_id
              , timestamp
              , hostname)
        VALUES (NULL, ?, ?, NOW(), ?)
        });
  $sth->execute($contig_id, $author_id, $contig_lock->hostname);
  my $contig_lock_id = $sth->{'mysql_insertid'}
  or throw('Failed to get new autoincremented ID for lock');
  $contig_lock->dbID($contig_lock_id);

  return;
}

sub remove {
  my( $self, $contig_lock ) = @_;
  $self->throw("Must provide a ContigLock to the remove method")
      unless $contig_lock;
  my $contig_id = $contig_lock->contig_id
      or $self->throw('contig_id not set on ContigLock object');
  my $sth = $self->prepare("DELETE FROM contig_lock WHERE seq_region_id = ?");
  $sth->execute($contig_id);
  $self->throw("Failed to remove ContigLock for contig " . $contig_id) unless $sth->rows;
  return;
}

1;







