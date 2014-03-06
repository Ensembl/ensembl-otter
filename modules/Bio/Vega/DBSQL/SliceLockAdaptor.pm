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
          , seq_region_start
          , seq_region_end
          , author_id
          , UNIX_TIMESTAMP(ts_begin)
          , UNIX_TIMESTAMP(ts_activity)
          , active
          , freed
          , freed_author_id
          , intent
          , hostname
          , UNIX_TIMESTAMP(ts_free)
        FROM slice_lock
        } . $where_clause);
  $sth->execute(@param);

  my $slicelocks=[];
  while (my $row = $sth->fetch) {
      my $slicelock = Bio::Vega::SliceLock->new
        (-ADAPTOR          => $self,
         -DBID             => $row->[0],
         -SEQ_REGION_ID    => $row->[1],
         -SEQ_REGION_START => $row->[2],
         -SEQ_REGION_END   => $row->[3],
         -AUTHOR       => $self->_author_find($row->[4]),
         -TS_BEGIN     => $row->[5],
         -TS_ACTIVITY  => $row->[6],
         -ACTIVE       => $row->[7],
         -FREED        => $row->[8],
         -FREED_AUTHOR => $self->_author_find($row->[9]),
         -INTENT       => $row->[10],
         -HOSTNAME     => $row->[11],
         -TS_FREE      => $row->[12],
        );
      push(@$slicelocks, $slicelock);
  }
  return $slicelocks;
}

sub _author_find {
    my ($self, $author_id) = @_;
    if (defined $author_id) {
        my $aad = $self->db->get_AuthorAdaptor;
        return $aad->fetch_by_dbID($author_id);
    } else {
        return undef;
    }
}

sub _author_dbID {
    my ($self, $what, $author) = @_;
    throw("$what not set on SliceLock object") unless $author;
    unless ($author->dbID) {
        my $aad = $self->db->get_AuthorAdaptor;
        $aad->store($author);
    }
    return $author->dbID;
}

sub fetch_by_dbID {
  my ($self, $id) = @_;
  if (!defined($id)) {
      throw("Id must be entered to fetch a SliceLock object");
  }
  my ($obj) = $self->_generic_sql_fetch("where slice_lock_id = ? ", $id);
  return $obj->[0];
}

sub fetch_by_seq_region_id {
  my ($self, $id, $extant) = @_;
  throw("Slice seq_region_id must be entered to fetch a SliceLock object")
      unless $id;
  throw("extant=0 not implemented") if defined $extant && !$extant;
  my $q = "where seq_region_id = ?";
  $q .= " and active <> 'free' and freed is null" if $extant;
  my $slicelocks = $self->_generic_sql_fetch($q, $id);
  return $slicelocks;
}


sub fetch_by_author {
  my ($self, $auth, $extant) = @_;
  throw("Author must be entered to fetch a SliceLock object")
      unless $auth;
  throw("extant=0 not implemented") if defined $extant && !$extant;
  my $authid = $self->_author_dbID(fetch_by => $auth);
  my $q = "where author_id = ?";
  $q .= " and active <> 'free' and freed is null" if $extant;
  my $slicelocks = $self->_generic_sql_fetch($q, $authid);
  return $slicelocks;
}


sub store {
  my ($self, $slice_lock) = @_;
  throw("Must provide a SliceLock object to the store method")
      unless $slice_lock;
  throw("Argument must be a SliceLock object to the store method.  Currently is [$slice_lock]")
      unless $slice_lock->isa("Bio::Vega::SliceLock");


  my $seq_region_id = $slice_lock->seq_region_id
    or $self->throw('seq_region_id not set on SliceLock object');

  my $author_id = $self->_author_dbID(author => $slice_lock->author);
  my $freed_author_id = defined $slice_lock->freed_author
    ? $self->_author_dbID(freed_author => $slice_lock->freed_author) : undef;

  if ($slice_lock->adaptor) {
#      $slice_lock->is_stored($slice_lock->adaptor->db)) {
      die "UPDATE or database move $slice_lock: not implemented";
  } else {
      my $sth = $self->prepare(q{
        INSERT INTO slice_lock(slice_lock_id
          , seq_region_id
          , seq_region_start
          , seq_region_end
          , author_id
          , ts_begin
          , ts_activity
          , active
          , freed
          , freed_author_id
          , intent
          , hostname
          , ts_free)
        VALUES (NULL, ?,?,?, ?, NOW(), NOW(), ?, ?, ?, ?, ?, NULL)
        });
      $sth->execute
        ($slice_lock->seq_region_id,
         $slice_lock->seq_region_start,
         $slice_lock->seq_region_end,
         $author_id,
         $slice_lock->active, $slice_lock->freed, $freed_author_id,
         $slice_lock->intent, $slice_lock->hostname);

      $slice_lock->adaptor($self);
      my $slice_lock_id = $self->last_insert_id('slice_lock_id', undef, 'slice_lock')
        or throw('Failed to get new autoincremented ID for lock');
      $slice_lock->dbID($slice_lock_id);

      $self->freshen($slice_lock);
  }

  return 1;
}

# After database engine has set timestamps or other fields,
# fetch them to keep object up-to-date
sub freshen {
    my ($self, $stale) = @_;
    my $dbID = $stale->dbID;
    throw("Cannot freshen an un-stored SliceLock") unless $dbID;
    my $fresh = $self->fetch_by_dbID($dbID);
    local $stale->{_mutable} = 'freshen';
    foreach my $field ($stale->FIELDS()) {
        my ($stV, $frV) = ($stale->$field, $fresh->$field);
        if (ref($stV) && ref($frV) &&
            $stV->dbID == $frV->dbID) {
            # object, with matching dbID --> no change
        } else {
            $stale->$field($frV);
        }
    }
    return;
}


sub unlock {
  my ($self, $slice_lock, $unlock_author, $freed) = @_;
  $freed = 'finished' if !defined $freed;
  my $dbID = $slice_lock->dbID;

  my $author_id = $self->_author_dbID(author => $slice_lock->author);
  my $freed_author_id = $self->_author_dbID(freed_author => $unlock_author)
    or throw "unlock must be done by some author";
  throw "SliceLock dbID=$dbID is already free"
    unless $slice_lock->is_held || $slice_lock->active eq 'pre';

  # the freed type is constrained, depending on freed_author
  if ($freed_author_id == $author_id) {
      # Original author frees her own lock
      throw "unlock type '$freed' inappropriate for same-author unlock"
        unless $freed eq 'finished';
  } else {
      # Somebody else frees her lock (presumably with good reason)
      my $a_email = $slice_lock->author->email;
      my $f_email = $unlock_author->email;
      throw "unlock type '$freed' inappropriate for $f_email acting on $a_email lock"
        unless grep { $_ eq $freed } qw( expired interrupted );
  }

  my $sth = $self->prepare(q{
    UPDATE slice_lock
    SET active='free', freed=?, freed_author_id=?, ts_free=now()
    WHERE slice_lock_id = ?
  });
  my $rv = $sth->execute($freed, $freed_author_id, $dbID);
  throw "UPDATE slice_lock SET active=free...: failed, rv=$rv"
    unless $rv == 1;

  $self->freshen($slice_lock);

  return 1;
}


1;
