package Bio::Vega::SliceLock;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Slice;

use Date::Format 'time2str';
use Try::Tiny;

use base qw(Bio::EnsEMBL::Storable);


=head1 NAME

Bio::Vega::SliceLock - a lock on part of a seq_region

=head1 DESCRIPTION

This behaves like a mostly read-only feature.

Changes are made to its fields during
L<Bio::Vega::DBSQL::SliceLockAdaptor/store> and through its broker.

=head2 Not actually a Feature

It is a Storable, not a Feature because

 All features in Ensembl inherit from the Bio::EnsEMBL::Feature class
 and have the following location defining attributes: start, end,
 strand, slice.

 All features also have the methods transform(), transfer(), and
 project() which are described in detail in the Transform, Transfer
 and Project sections of this tutorial.

Locks have no strand.

They must not be moved onto a different slice for any reason without
creating a new lock at the new location.

=cut

sub FIELDS() {
    return
      (qw( seq_region_id seq_region_start seq_region_end ),
       qw( ts_begin ts_activity ts_free ), # unixtimes
       qw( active freed ),        # enums.  database will check
       qw( author freed_author ), # objects
       qw( intent hostname otter_version ));    # text
# qw(dbID adaptor) are supplied by base class
}


sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);

    my ($slice, %val);
    ($slice, @val{FIELDS()}) =
      rearrange([ 'SLICE', map { uc($_) } FIELDS() ], @args);

    # defaults
    $val{active} = 'pre' if !defined $val{active};
    if (defined $slice) {
        my @overspec = grep { defined $val{$_} }
          qw( seq_region_id seq_region_start seq_region_end );
        throw "Cannot instantiate SliceLock with -SLICE and \U(@overspec)"
          if @overspec;
        $val{seq_region_id} = $slice->adaptor->get_seq_region_id($slice);
        $val{seq_region_start} = $slice->start;
        $val{seq_region_end} = $slice->end;
    }

    my ($start, $end) = @val{qw{ seq_region_start seq_region_end }};
    throw "Cannot instantiate SliceLock with backwards Slice (start $start > end $end)"
      if $start > $end;

    local $self->{_mutable} = 'new';
    while (my ($field, $val) = each %val) {
        $self->$field($val);
    }

    # When not loaded from DB, there are extra constraints
    my $sla = $self->adaptor;
    $self->_check_new_lock
      unless $sla && $self->dbID && $self->is_stored($sla->db);

    # We don't migrate these between databases.  (Store and stay)
    throw("Cannot instantiate SliceLock with (SliceLockAdaptor xor dbID)")
      if $sla xor $self->dbID;

    return $self;
}

sub _check_new_lock {
    my ($self) = @_;

    # Freshly made lock must be a "pre" lock, not "held".
    # The locking step is done by the adaptor.
    my $active = $self->active;
    throw("Fresh SliceLock must have active=pre, this is active=$active")
      unless $active eq 'pre';

    throw("Fresh SliceLock must not be freed")
      if grep {defined} ($self->freed, $self->ts_free, $self->freed_author);

    # Timestamps are set by the adaptor.
    my @ts = ($self->ts_begin, $self->ts_activity, $self->ts_free);
    if (grep {defined} @ts) {
        my @show_ts = map { defined($_) ? $_ : 'null' } @ts;
        throw("Fresh SliceLock must have null timestamps, this has [@show_ts]");
    }

    return;
}


sub dbID {
    my $self = shift;
    if (@_) {
        # write
        my $newId = shift;
        my $oldId = $self->SUPER::dbID();
        throw("dbID is immutable") if defined $oldId;
        return $self->SUPER::dbID($newId);
    } else {
        # read
        return $self->SUPER::dbID();
    }
}

sub adaptor {
    my $self = shift;
    if (@_) {
        # write
        my $newAdap = shift;
        my $oldAdap = $self->SUPER::adaptor();
        throw("adaptor is immutable") if defined $oldAdap;
        return $self->SUPER::adaptor($newAdap);
    } else {
        # read
        return $self->SUPER::adaptor();
    }
}


=head2 is_held()

Return true iff the lock is currently (according to what is in memory)
excluding others from the slice.

=cut

sub is_held {
    my ($self) = @_;
    return ($self->active eq 'held' && !$self->freed) ? 1 : 0;
}


=head2 is_held_sync()

Return true iff the lock is currently (according to database as seen
from this connection) excluding others from the slice, after
L<Bio::Vega::DBSQL::SliceLockAdaptor/freshen> has updated the
in-memory properties.

This is a convenience wrapper around C<freshen> and L</is_held>.  It
synchronises, but does not obtain explicit database row locks.
B<Caveats apply when two connections have overlapping transactions!>

=over 4

=item * REPEATABLE-READ (the default)

B<This call would not prevent the SliceLock becoming free
(e.g. C<interrupted>) while you are using it>.  To do that for the
duration of a database transaction, use L</bump_activity> without a
C<commit>.

=item * SERIALIZABLE isolation

When a transaction has been opened, the C<freshen> call causes a
C<SELECT ... LOCK IN SHARE MODE> and so may wait for lock timeout.
L</bump_activity> is still needed to get an exclusive lock before
writing.

=back

=cut

sub is_held_sync {
    my ($self) = @_;
    $self->adaptor->freshen($self);
    return $self->is_held;
}


=head2 slice()

Convenience method to create and return a L<Bio::EnsEMBL::Slice> for
the locked region.

The lock must have been stored and the slice must be valid.

=cut

sub slice {
    my ($self) = @_;
    my $SLdba = $self->adaptor;
    throw "$self cannot make slice without adaptor" unless $SLdba;
    my @pos =
      ($self->seq_region_id,
       $self->seq_region_start,
       $self->seq_region_end);
    my $sl = $SLdba->db->get_SliceAdaptor->fetch_by_seq_region_id(@pos)
      or throw "invalid slice (@pos)";
    return $sl;
}


=head2 bump_activity()

Convenience method to UPDATE the ts_activity field to now and freshen
the lock, returning true.

The lock must have been stored.

=cut

sub bump_activity {
    my ($self) = @_;
    my $SLdba = $self->adaptor;
    throw "$self cannot make slice without adaptor" unless $SLdba;
    return $SLdba->bump_activity($self);
}


=head2 exclusive_work($code, $unlock)

Will call C<COMMIT> multiple times, via L</adaptor>.

Convenience method for L<Bio::Vega::DBSQL::SliceLockAdaptor/Workflow>,
which takes on a SliceLock in any of these states

=over 4

=item * pre

The call to L<Bio::Vega::DBSQL::SliceLockAdaptor/store> has been made,
so there is an L</adaptor> and L</dbID>.

This method calls L<Bio::Vega::DBSQL::SliceLockAdaptor/do_lock> for
you.

=item * held

Ready to begin an exclusive chunk of work

=back

and will proceed with the workflow, assuming no errors happen:

=over 4

=item 1. C<COMMIT>

=item 2. reach C<active='held'>

=item 3. C<COMMIT>

=item 4. C<bump_activity>

=item 5. Call $code

Currently with no arguments, ignoring the return value.

Rollback is called for you if something goes wrong.

=item 6. C<COMMIT>

=item 7. If $unlock, then C<unlock> and C<COMMIT> again

=back

or produce some meaningful error messages in the common cases where
things can go wrong.

Returns nothing if everything was done.  Returns the error message (as
a true value, also sent as a warning) if just the unlock failed.
Other errors may be raised.

=cut

sub exclusive_work {
    my ($self, $code, $unlock) = @_;

    # 1.  Storing the lock has been done already.
    my $adap = $self->adaptor;
    throw "Cannot proceed without an adaptor"
      unless $adap && $self->dbID && $self->is_stored($adap->db);
    my $dbh = $adap->dbc->db_handle;

    my $rollback = sub {
        my ($err_ref) = @_;
        chomp $$err_ref;
        try {
            $dbh->rollback;
        } catch {
            $$err_ref .= "; then rollback failed: $_";
            chomp $$err_ref;
        };
        return;
    };

    my $commit = sub {
        my ($want_txn) = @_;
        $dbh->begin_work if $dbh->{AutoCommit}; # avoid warning
        $dbh->commit;
        $dbh->begin_work if $want_txn;
        return;
    };

    # 2.
    if ($self->active eq 'pre') {
        $commit->(1); # as up-to-date as we can get
        try {
            $adap->do_lock($self) or die "lost the race";
        } catch {
            my $err = $_;
            chomp $err;
            my $what = $self->describe;
            $commit->(1);
            throw "Cannot proceed, do_lock failed <$err> leaving $what";
        };
    } # else active=held and we're OK,
    # or active=free and 3. will make the error.

    # 3.
    $commit->(1);
    if (!$self->is_held_sync) {
        my $what = $self->describe;
        throw "Cannot proceed, not holding the lock $what";
    }

    # 4.
    try {
        $adap->bump_activity($self);
    } catch {
        my $err = $_;
        $rollback->(\$err);
        my $what = $self->describe('rollback');
        throw "Cannot proceed, lock busy?  error=<$err> on $what";
    };

    ### Got here - we have the region exclusively
    try {
        # 5.
        $code->();
        # 6.
        $commit->(0);
    } catch {
        my $err = $_;
        $rollback->(\$err);
        my $what = $self->describe('rollback');
        throw "SliceLock held but work failed.  error=<$err> on $what";
    };

    # 7.
    if ($unlock) {
        # Unlock could fail, but that is probably less serious
        my $err = try {
            $adap->unlock($self, $self->author);
            $commit->(0);
            '';
        } catch {
            $_ || "Failed: $_";
        };
        chomp $err if $err;

        my $what = $self->describe;
        if ($self->is_held) {
            # unlock failed
            warn "Work completed but unlock failed.  error=<$err> on $what";
            return $err;
        } else {
            # success, but maybe not how we planned it
            warn "Work completed, but during unlock there was an error=<$err> on $what"
              if $err;
            return ();
        }
    } else {
        # success
        return ();
    }
}


sub _init {
    my ($pkg) = @_;
    my %new_method;
    my %author = (author => 1, freed_author => 1);

    # Simple r/w accessors
    foreach my $field (FIELDS()) {
        $new_method{$field} = sub {
            my ($self, $newval) = @_;
            if (@_ > 1) { # qw( freed freed_author ts_free otter_version ) are nullable
                # some fields would be safe to mutate and save,
                # but currently we only allow write during new
                throw("$field is frozen") if !$self->{_mutable};
                throw("Argument [$newval] is not a Bio::Vega::Author")
                  if $author{$field} && defined $newval &&
                    !eval { $newval->isa("Bio::Vega::Author") };
                $self->{$field} = $newval;
            }
            return $self->{$field};
        };
    }

    # Times are in unixtime.  Add extra time accessors.
    foreach my $field (qw( ts_begin ts_activity ts_free )) {
        $new_method{"iso8601_$field"} = sub {
            my ($self) = @_;
            throw("$field is read-only") if @_ > 1;
            my $unixtime = $self->$field;
            return defined $unixtime ? __iso8601($unixtime) : 'Tundef';
        };
    }

    while (my ($field, $code) = each %new_method) {
        no strict 'refs';
        *{"$pkg\::$field"} = $code;
    }

    return;
}

sub __iso8601 {
    my ($t) = @_;
    return time2str('%Y-%m-%d %T %Z', $t, 'GMT');
}


=head2 describe($was_rolled_back)

Returns a string explaining the current state of the object, catching
any exceptions and providing alternative text.

If the optional C<$was_rolled_back> is true, the explanation is marked
as showing the state B<before a rollback>.

XXX: Tells nothing about the species or dataset name.  Wider context
should cover this.

=cut

sub describe {
    my ($self, $rolledback) = @_;

    # should make no reference to ->adaptor, because we may want to
    # run it on a serialised-to-client copy

    my $act = $self->active;
    my $dbID = $self->dbID;
    my ($state, $detail);
    if (!$dbID && $act eq 'pre') {
        $state = "'pre(new)'";
        $detail = 'Not yet saved to database';
    } elsif ($act eq 'free') {
        my $freed = $self->freed;
        my $by = '';
        $by = ' by '.$self->freed_author->email
          if $self->freed_author && $self->freed_author->dbID != $self->author->dbID;
        $state = sprintf("'free(%s)'%s since %s",
                         $freed, $by, $self->iso8601_ts_free);
        $detail = { finished => 'The region was closed',
                    too_late => 'Lost the race to lock the region',
                    interrupted => 'The lock was broken',
                    expired => 'The lock was broken' }->{$freed} || 'WEIRD';
    } else {
        $state = "'$act'";
        $detail = { pre => 'The region is not yet locked',
                    held => 'The region is locked' }->{$act} || 'WEIRD';
    }

    my $slice = try {
        $self->slice->display_id;
    } catch {
        # most likely the slice is invalid
        sprintf("BAD:srID=%s:start=%s:end=%s",
                $self->seq_region_id,
                $self->seq_region_start,
                $self->seq_region_end);
    };

    my $auth = try { $self->author->email } catch { "<???>" };

    return sprintf
      ('SliceLock(%s%s) on %s '.
       'was created %s by %s on host %s to "%s"%s '.
       "last active %s and now %s\n  %s.",
       $dbID ? ('dbID=', $dbID) : ('', 'not stored'), $slice,
       $self->iso8601_ts_begin, $auth, $self->hostname, $self->intent,
       ($rolledback ? ".  Before $rolledback, it was" : ','),
       $self->iso8601_ts_activity, $state, $detail);
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
