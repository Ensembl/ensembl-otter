=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Bio::Vega::DBSQL::SliceLockAdaptor;

use strict;
use warnings;
use Try::Tiny;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Vega::DBSQL::AuthorAdaptor;
use Bio::Vega::SliceLock;

use base qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);


=head1 NAME

Bio::Vega::DBSQL::SliceLockAdaptor - handle SliceLock objects


=head1 SYNOPSIS

 my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
 # ...
 $SLdba->store($lock);
 $SLdba->do_lock($lock);
 $SLdba->unlock($lock, $lock->author);
 # see workflow below, for places the caller should COMMIT


=head1 DESCRIPTION

This is a region-exclusive lock attached directly to a slice and
operates like a feature.

It does not affect other slices which map to the same sequence.

=head2 Workflow

The safe workflow is wrapped up in the convenience method
L<Bio::Vega::SliceLockBroker/exclusive_work> but you can use the parts
directly:

=over 4

=item 1. Create lock in state C<active='pre'>; store it.

It has not yet left your transaction.

=item 2. COMMIT; Call L</do_lock> to reach state C<active='held'>

Your SliceLock becomes visible to other database sessions, and you can
see recent SliceLocks from elsewhere.

Check the return value.  Maybe someone else got the lock.

=item 3. COMMIT; Check L<Bio::Vega::SliceLock/is_held_sync>

If the lock was broken from outside, you find out without having to
catch an exception.

=item 4. L<Bio::Vega::SliceLock/bump_activity>

The region is now exclusively yours.

=item 5. Update rows as necessary; COMMIT

The SliceLock remains valid, but could now be C<interrupted> by
another user or used by another action by the same user.

=item 6. Repeat 3 .. 5 as necessary.

Updates may be made within the region over a longer period of time.
Other users can see (by ts_activity) whether there was recent
activity.

=item 7. L</unlock>; COMMIT

As with C<is_held_sync>, this can fail, so be prepared to roll back.

XXX: no, it must not if we checked is_held_sync already!  it would be too late to roll back

XXX: presumably if the lock is in use elsewhere (then not if you didn't commit after work), or something else freed it already - this should return not fail.

=back

This workflow can be broken (at the COMMIT points) between runtime
instances, because the lock object persists in the database.


=head2 Other possible operations - dibs

In order to use the 'pre' state as a non-binding "dibs" on a region,
it might be useful for its owner to be able to split a 'pre' lock on a
Slice into two locks on smaller contiguous regions.

Possibly this should be done in another state, to avoid the need to
check over the entire state machine for locking operations.


=head1 METHODS

=cut


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
          , otter_version
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
         -OTTER_VERSION => $row->[12],
         -TS_FREE      => $row->[13],
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
        return undef; ## no critic (Subroutines::ProhibitExplicitReturnUndef)
        # ...to put one element 'undef' in the caller's arglist
    }
}

# Not particularly public, but used by SliceLockBroker
sub author_dbID {
    my ($self, $what, $author) = @_;
    throw("$what not set on SliceLock object") unless $author;
    unless ($author->dbID) {
        my $aad = $self->db->get_AuthorAdaptor;
        $aad->store($author);
    }
    return $author->dbID;
}


=head2 fetch_by_dbID($id)

Return one SliceLock.

=head2 fetch_by_seq_region_id($sr_id, $extant)

If provided, $extant must be true.
Then freed locks are ignored; pre locks are still returned.

Returns arrayref of SliceLock.

=head2 fetch_by_active($active)

$active defaults to C<held>.

Returns arrayref of SliceLock.

=cut

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
  my $authid = $self->author_dbID(fetch_by => $auth);
  my $q = "where author_id = ?";
  $q .= " and active <> 'free' and freed is null" if $extant;
  my $slicelocks = $self->_generic_sql_fetch($q, $authid);
  return $slicelocks;
}


sub fetch_by_active {
    my ($self, $active) = @_;
    $active ||= 'held';
    my $q = "where active = ?";
    my $slicelocks = $self->_generic_sql_fetch($q, $active);
    return $slicelocks;
}


sub _sane_db {
    my ($self) = @_;
    my $dbh = $self->dbc->db_handle;

    # Things to check
    my %info = (RaiseError => $dbh->{'RaiseError'});
    my $row = $dbh->selectall_arrayref(q{
      SELECT @@tx_isolation, engine
      FROM information_schema.tables
      WHERE table_schema=database() and table_name='slice_lock'
    });

    throw("_sane_db expected one row for `slice_lock`, got ".@$row)
      unless 1 == @$row; # happens when the table is missing!
    @info{qw{ tx_isolation engine }} = @{ $row->[0] };

    if ($info{engine} eq 'InnoDB' &&
        $info{RaiseError} &&
        # READ-UNCOMMITTED READ-COMMITTED can't be tested with our
        # slave setup and we don't need them - reject
        (grep { $_ eq $info{tx_isolation} }
         qw{ REPEATABLE-READ SERIALIZABLE })) {
        return 1;
    } else {
        my @info = map {"$_=$info{$_}"} sort keys %info;
        throw("_sane_db: cannot run with (@info)");
    }
}

sub _is_our_lock {
    my ($self, $lock) = @_;
    my $adap = $lock->adaptor;
    if (defined $adap && $adap != $self) {
        my $dbID = $lock->dbID;
        throw("$self: Lock $lock (dbID=$dbID) was fetched/stored with different adaptor $adap");
    }
    return;
}


sub store {
  my ($self, $slice_lock) = @_;
  throw("store($slice_lock): not a SliceLock object")
      unless try { $slice_lock->isa('Bio::Vega::SliceLock') };

  throw("Argument must be a SliceLock object to the store method.  Currently is [$slice_lock]")
      unless $slice_lock->isa("Bio::Vega::SliceLock");


  my $seq_region_id = $slice_lock->seq_region_id
    or $self->throw('seq_region_id not set on SliceLock object');

  my $author_id = $self->author_dbID(author => $slice_lock->author);
  my $freed_author_id = defined $slice_lock->freed_author
    ? $self->author_dbID(freed_author => $slice_lock->freed_author) : undef;

  $self->_sane_db;
  if ($slice_lock->adaptor) {
#      $slice_lock->is_stored($slice_lock->adaptor->db)) {
      $self->_is_our_lock($slice_lock);
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
          , otter_version
          , ts_free)
        VALUES (NULL, ?,?,?, ?, NOW(), NOW(), ?, ?, ?, ?, ?, ?, NULL)
        });
      $sth->execute
        ($slice_lock->seq_region_id,
         $slice_lock->seq_region_start,
         $slice_lock->seq_region_end,
         $author_id,
         $slice_lock->active, $slice_lock->freed, $freed_author_id,
         $slice_lock->intent, $slice_lock->hostname, $slice_lock->otter_version);

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
    throw "freshen($stale): not a SliceLock object"
      unless try { $stale->isa('Bio::Vega::SliceLock') };

    my $dbID = $stale->dbID;
    throw("Cannot freshen an un-stored SliceLock") unless $dbID;
    $self->_is_our_lock($stale);
    $self->_sane_db;
    my $fresh = $self->fetch_by_dbID($dbID);
    throw("Freshen(dbID=$dbID) failed, row not found")
      unless $fresh; # should not happen
    local $stale->{_mutable} = 'freshen';
    my @change = ("$stale->freshen($dbID)");
    foreach my $field ($stale->FIELDS()) {
        my ($stV, $frV) = ($stale->$field, $fresh->$field);
        if (ref($stV) && ref($frV) &&
            $stV->dbID == $frV->dbID) {
            # object, with matching dbID --> no change
        } else {
            my $old = $stale->$field;
            $stale->$field($frV);
            $old='undef' unless defined $old;
            $frV='undef' unless defined $frV;
            push @change, "[$field, old=$old new=$frV]"
              if ref($frV) || ref($old) || $old ne $frV;
        }
    }
    # warn "@change\n";
    return;
}


=head2 do_lock($lock)

Given a lock in the C<active='pre'> state, attempt to bring it to
C<active='held'>.

On return the object will have been L</freshen>ed to match the
database.  The return value is true for success, false for an ordinary
failure where something else got there first.

Exceptions may be raised if $lock was in some unexpected state.

=cut

sub do_lock {
    my ($self, $lock, $debug) = @_;
    throw "do_lock($lock ...): not a SliceLock object"
      unless try { $lock->isa('Bio::Vega::SliceLock') };

    # relevant properties
    my ($lock_id, $active, $ts_begin, $srID, $sr_start, $sr_end) =
      ($lock->dbID, $lock->active, $lock->ts_begin,
       $lock->seq_region_id, $lock->seq_region_start, $lock->seq_region_end);
    my $author_id = $self->author_dbID(author => $lock->author);

    throw("do_lock: $lock has not been stored") unless $lock_id;
    throw("do_lock($lock_id) failed: expected active=pre, got active=$active")
      unless $active eq 'pre';
    $self->_sane_db;
    $self->_is_our_lock($lock);

    # Check for non-free locks on our slice
    my ($seen_self, @too_late) = (0);
    my $sth_check = $self->prepare(q{
      SELECT slice_lock_id, active, freed
      FROM slice_lock
      WHERE (active in ('pre', 'held') -- could affect us, or be us
             or ts_free >= ?)          -- could be us (limit to recent)
        AND seq_region_id = ?          -- overlapping slice
        AND seq_region_end >= ?
        AND seq_region_start <= ?
    });
    $sth_check->execute($ts_begin, $srID, $sr_start, $sr_end);
    while (my $row = $sth_check->fetch) {
        my ($ch_slid, $ch_act, $ch_freed) = @$row;
        if ($ch_slid == $lock_id) {
            # our lock
            if ($ch_act eq 'pre') {
                $seen_self ++;
            } elsif ($ch_act eq 'free' && $ch_freed eq 'too_late') {
                $seen_self ++;
                push @too_late, "before stale do_lock, by slid=$ch_slid";
            } else {
                # Shouldn't happen when following the Workflow
                $ch_freed = '' if !defined $ch_freed;
                throw "do_lock($ch_slid) failed: input not fresh - active='$ch_act' freed='$ch_freed'";
                # Someone else *could* set free(interrupted) or
                # free(expired) on our pre-lock, but they should not.
            }
        } else {
            # a potentially competing lock, overlapping in space && time
            if ($ch_act eq 'pre') {
                # Potential race: either they will free(too_late) us,
                # we will free(too_late) them in our next query.
            } elsif ($ch_act eq 'free') {
                # Some lock which was already freed.  Relevant only
                # for debug - it may have locked (freeing us) and gone
                push @$debug, "saw slid=$ch_slid $ch_act($ch_freed)"
                  if defined $debug;
            } elsif ($ch_act eq 'held') {
                # Either our 'pre' was added after their 'held'
                # existed, so they didn't UPDATE us to free(too_late);
                # or we have been UPDATEd to free(too_late) already.
                push @too_late,
                  "early do_lock / before insert, by slid=$ch_slid";
            } else {
                throw "impossible - ch_act=$ch_act";
            }
        }
    }
    throw("do_lock($lock_id) failed: did not see our row match")
      unless $seen_self;

    if (@too_late) {
        # "Early" too_late detection above.  This tidy up is required
        # for the pre-exising-"held" case.
        my $sth_free = $self->prepare(q{
      UPDATE slice_lock
      SET active='free'
        , freed='too_late'
        , ts_free=now()
      WHERE slice_lock_id = ?
        AND active <> 'free'
        });
        my $rv = $sth_free->execute($lock_id);
        push @too_late, "(tidy rv=$rv)"; # for debug only

    } else {
        # Have a chance for the lock.  Do atomic update for exclusion
        my $sth_activate = $self->prepare(q{
      UPDATE slice_lock
      SET active          = if(slice_lock_id = ?, 'held', 'free')
        , ts_activity     = if(slice_lock_id = ?, now(), ts_activity)
        , freed           = if(slice_lock_id = ?, null, 'too_late')
        , ts_free         = if(slice_lock_id = ?, null, now())
        , freed_author_id = if(slice_lock_id = ?, null, ?)
      WHERE active='pre'
        AND seq_region_id = ?
        AND seq_region_end >= ?
        AND seq_region_start <= ?
        });
        my $rv = $sth_activate->execute
          ($lock_id, $lock_id, $lock_id, $lock_id, $lock_id,
           $author_id,
           $srID, $sr_start, $sr_end);
        push @too_late, # for debug only
          $rv > 0 ? "race looks won? (rv=$rv)" : "beaten in race? (rv=$rv)";
    }

    push @$debug, @too_late if defined $debug;
    # push @$debug, [ adaptor => $lock->adaptor ], [ old => { %$lock } ];
    $self->freshen($lock);
    # push @$debug, [ freshened => { %$lock } ];

    $active = $lock->active;
    if ($active eq 'free') {
        return 0;
    } elsif ($active eq 'held') {
        return 1;
    } else {
        my $info = $debug ? (join "\n    ", ' @$debug=', @$debug) : "";
        throw "do_lock($lock_id) confused, active=$active$info";
    }
}


=head2 bump_activity($lock)

Attempt to UPDATE the ts_activity field to now, then attempt to
L</freshen> the lock to match the database.

Exception raised if $lock was not updated.  This may be due to a lock
timeout (something else using this SliceLock) or asynchronous
SliceLock removal.

Otherwise returns true, and you have exclusive use of this valid
SliceLock until you C<commit> or C<rollback>.

=cut

sub bump_activity {
    my ($self, $lock) = @_;
    throw "bump_activity($lock): not a SliceLock object"
      unless try { $lock->isa('Bio::Vega::SliceLock') };

    my $dbID = $lock->dbID;
    $self->_sane_db;
    $self->_is_our_lock($lock);
    my $sth = $self->prepare(q{
      UPDATE slice_lock
      SET ts_activity = now()
      WHERE slice_lock_id = ?
        AND active='held'
    });
    my $rv = $sth->execute($dbID);
    $self->freshen($lock);
    if ($rv == 1) {
        return 1;
    } else {
        my $act = $lock->active;
        throw "bump_activity($lock): failed, rv=$rv dbID=$dbID active=$act";
    }
}


=head2 unlock($slice_lock, $unlock_author, $freed)

$freed defaults to C<finished>, which is the expected value when
$unlock_author is the lock owner.  Other authors must set $freed to
C<interrupted> or C<expired>, and be able to justify doing this if
asked about it later.

Throws an exception if the lock was already free in-memory.

Attempts to free $slice_lock and L</freshen> its properties from the
database.

Throws an exception if the lock was freed asynchronously in the
database (e.g. to the C<freed(interrupted)> state), or row locks time
out during the attempt.

Otherwise, returns true.

=cut

sub unlock {
  my ($self, $slice_lock, $unlock_author, $freed) = @_;
  $freed = 'finished' if !defined $freed;
  throw "unlock($slice_lock ...): not a SliceLock object"
    unless try { $slice_lock->isa('Bio::Vega::SliceLock') };

  my $dbID = $slice_lock->dbID;
  my $author_id = $self->author_dbID(author => $slice_lock->author);
  my $freed_author_id = $self->author_dbID(freed_author => $unlock_author)
    or throw "unlock must be done by some author";
  throw "SliceLock dbID=$dbID is already free (in-memory)"
    unless $slice_lock->is_held || $slice_lock->active eq 'pre';

  # the freed type is constrained, depending on freed_author
  if ($freed_author_id == $author_id) {
      # Original author frees her own lock; interrupt or expire
      # suggest unlocking not via original UI.
      throw "unlock type '$freed' inappropriate for same-author unlock"
        unless grep { $_ eq $freed } qw( expired interrupted finished );
  } else {
      # Somebody else frees her lock (presumably with good reason)
      my $a_email = $slice_lock->author->email;
      my $f_email = $unlock_author->email;
      throw "unlock type '$freed' inappropriate for $f_email acting on $a_email lock"
        unless grep { $_ eq $freed } qw( expired interrupted );
  }

  $self->_sane_db;
  $self->_is_our_lock($slice_lock);
  my $sth = $self->prepare(q{
    UPDATE slice_lock
    SET active='free', freed=?, freed_author_id=?, ts_free=now()
    WHERE slice_lock_id = ?
      AND active <> 'free'
  });
  my $rv = $sth->execute($freed, $freed_author_id, $dbID);

  $self->freshen($slice_lock);

  if ($rv == 1) {
      return 1;
  } else {
      throw "SliceLock dbID=$dbID was already free (async lock-break?).  UPDATE...SET active=free... failed, rv=$rv";
  }
}

sub pod_CREATE_TABLE {
    my ($called, $strip_readables) = @_;
    my $fn = __FILE__;
    open my $fh, '<', $fn or die "Read $fn: $!";
    my @txt = grep { /^=begin sql/ .. /=end sql/ } <$fh>;
    shift @txt; # =begin
    pop @txt; # =end
    my $txt = join '', @txt;
    __sql_regularise(\$txt) if $strip_readables;
    return $txt;
}

sub db_CREATE_TABLE {
    my ($self, $strip_dull) = @_;
    my $dbh = $self->dbc->db_handle;
    my (undef, $txt) = $dbh->selectrow_array(q{ SHOW CREATE TABLE slice_lock });
    __sql_regularise(\$txt) if $strip_dull;
    return $txt;
}

sub __sql_regularise {
    my ($txtref) = @_;
    for ($$txtref) {
        # Human readableness
        s{(^| )-- .*$}{}mg;
        s{ +\n}{\n}g;
        s{[ \t]+}{ }g;
        s{\n+\Z}{};
        s{int unsigned}{int(10) unsigned}g;
        s{int }{int(11) }g;

        # Database output
        s{`}{}g;
        s{ AUTO_INCREMENT=\d+ }{ };
        s{\b(CREATE TABLE|(NOT|DEFAULT) NULL|AUTO_INCREMENT|PRIMARY|KEY)\b}{\L$1}g;

        s{,[ \t]*}{, }g;
        s{^[ \t\n]+}{}mg;
    }
    return;
}



=begin sql

-- adaptor like a feature?  a simple_feature or a new thing?

create table slice_lock (
 -- feature-like aspect
 slice_lock_id    int unsigned not null auto_increment,
 seq_region_id    int unsigned not null,
 seq_region_start int unsigned not null,
 seq_region_end   int unsigned not null,
 author_id        int          not null,      -- whose it is

 ts_begin         datetime     not null,      -- when row is INSERTed
 ts_activity      datetime      not null,     -- when the owner last touched it

 -- Transitions allowed: INSERT -> pre -> free(too_late),
 --   pre -> held -> free(finished | expired | interrupted)
 active           enum('pre', 'held', 'free')                            not null,
 freed            enum('too_late', 'finished', 'expired', 'interrupted') default null,
 freed_author_id  int default null,           -- who ( did / will ) free it

 -- FYI fields
 intent		  varchar(100) not null, -- human readable, some conventions or defaults?
 hostname         varchar(100) not null,          -- machine readable
 otter_version    varchar(16) default null,       -- machine readable, where relevant
 ts_free          datetime default null,          -- when freed was set

 primary key            (slice_lock_id),
 key seq_region_idx     (seq_region_id, seq_region_start),
 key active_author_idx  (active, author_id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1

=end sql


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
