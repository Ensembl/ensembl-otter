=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Bio::Vega::SliceLockBroker;

use strict;
use warnings;

use List::MoreUtils 'uniq';
use Try::Tiny;

use Bio::Vega::DBSQL::SliceLockAdaptor;
use Bio::EnsEMBL::Utils::Exception qw ( throw );
use Bio::Otter::Version;
use List::Util qw( min max );


=head1 NAME

Bio::Vega::SliceLockBroker - manage a SliceLock

=head1 SYNOPSIS

  my $br = Bio::Vega::SliceLockBroker->new
    (-hostname => $h, -author => $a);
  my $l = $br->lock_create_for_Slice(-slice => $slice);
  ...; # XXX: workflow here
  $br->unlock($a);

=head1 DESCRIPTION

Management of SliceLocks (aka. chromosome range locks) in a package
similar to the old L<Bio::Vega::ContigLock>s.

The plan is to put the relevant lock(s) you hold into this box, then
ask it to do operations on the locked regions.  Locks (plural) allows
this code to manage movement between chromosomes in one transaction.

SliceLocks must be created and locked, and then during the transaction
must also be C<bump_activity>d.  It is not enough to just have a
"locked" one sitting in the table while storing other objects, as it
was with L<Bio::Vega::ContigLock>s.

=head2 Comparison with ContigLockBroker

SliceLocks can cover an arbitrary range of any seq_region (normally a
chromosome).  They are persistent after they have been used and
unlocked, leaving an foreign-key-able indication that "something
happened" in that region.

The mapping from ContigLockBroker methods is

=over 4

=item new

SliceLockBroker must be construct or configured with something that
tells the database.  It also has one author and hostname.

=item check_locks_exist_by_slice, check_slice_argument

During L</exclusive_work>, use L</assert_bumped> to ensure that the
region you will operate upon is actually locked.

=item check_no_locks_exist_by_slice

Not implemented; nothing calls it.

=item lock_clones_by_slice

L</lock_create_for_Slice> and then use L</exclusive_work> to wrap the
work+commit.

=item lock_by_object

Pass all the objects at once to L</lock_create_for_objects>, then
continue as for C<lock_clones_by_slice>.

=item remove_by_object, remove_by_slice

Locks created may be unlocked individually via the adaptor.

If you want to unlock everything put into the broker,
L</exclusive_work> can do that as it finishes.

=back

Unlike the ContigLock, it is not enough to have the SliceLock in the
database.  We want to be assured that no other process is operating
under the cover of that same row in the C<slice_lock> table!

The L<Bio::Vega::DBSQL::SliceLockAdaptor/bump_activity> method does
this, and is wrapped up with error catching, COMMIT and ROLLBACK in
the L</exclusive_work> method.


=head1 CAVEATS

=over 4

=item One database

If you need to commit to two databases at once, SliceLockBroker will
need teaching to understand which COMMIT operates where and how to
approximate a two-phase commit.

=item Objects fetched before locks start

SliceLockBroker currently offers no method to refresh or reload the
objects; L</lock_create_for_objects> locks created are not yet "held"
but still "pre"; L</foreach_object> is cast in terms of objects
already loaded.

It is possible for these objects to change between the "load" and lock
acquisition.  It would also be possible for callers of SliceLockBroker
to prevent this, but most (so far) do not bother.

Scripts performing bulk updates on objects loaded before locking are
protected from long-duration locks held by the GUI, but there remains
a (vanishingly small) possibility of edit collisions between scripts.

=back


=head1 METHODS

=head2 new(-hostname => $h, -author => $a, -adaptor => $dba, -locks => $bvsl, -lockid => $bvsl_id)

Instantiate with any of host, author and/or locks.  Before work is
done, a lock must be provided by any of the various methods.

To fetch L<Bio::Vega::SliceLock>s by their C<slice_lock_id>s, the
broker must be tied to a database via
L<Bio::Vega::DBSQL::AuthorAdaptor> or
L<Bio::Vega::DBSQL::SliceLockAdaptor>.

C<$bvsl> and C<$bvsl_id> may be given as scalar (object or dbID
respectively), or arrayref of such.

=cut

sub new {
    my ($class, %arg) = @_;
    my $self = bless { locks => [] }, $class;

    foreach my $prop (qw( hostname adaptor author locks )) {
        my $key = "-$prop";
        $self->$prop(delete $arg{$key}) if exists $arg{$key};
    }
    $self->locks_add_by_dbID(delete $arg{'-lockid'}) if exists $arg{'-lockid'};

    my @left = sort keys %arg;
    throw "Rejected unrecognised args (@left)" if @left;

    return $self;
}


=head2 hostname

=head2 client_hostname

Acessor for hostname string.

Error on setting a mismatched hostname, or trying to fetch before it
is known.

=head2 adaptor

Accessor for the L<Bio::Vega::DBSQL::SliceLockAdaptor>.  May be set
explicitly as any DatabaseAdaptor that can provide one, or will be
inferred from any stored lock or author.

Error on setting a mismatched one, or trying to fetch it before it is
known.

=head2 author

Acessor for L<Bio::Vega::Author> object.

Error on setting a mismatched one, or trying to fetch it before it is
known.

For convenience, this may be set as the string C<for_uid> to infer the
author from the process UID.  The L</adaptor> must have been set
already.

=cut

sub client_hostname { # synonym, as in ContigLockBroker
    my ($self, @arg) = @_;
    return $self->hostname(@arg);
}

sub hostname {
    my ($self, @set) = @_;
    my ($L) = $self->locks;
    my $L_h = $L && $L->hostname;
    $self->{hostname} = $L_h if $L && !defined $self->{hostname};
    $L_h = $self->{hostname} if defined $self->{hostname};
    if (@set) {
        my ($hostname) = @set;
        throw "Cannot unset hostname" unless defined $hostname;
        throw "Cannot set multiple hostname" if @set > 1;
        throw "hostname mismatch: have $L_h, tried to set $hostname"
          if defined $L_h && $L_h ne $hostname;
        $L_h = $self->{hostname} = $hostname;
    }
    throw "hostname not yet available" unless defined $L_h;
    return $L_h;
}


sub adaptor {
    my ($self, @set) = @_;
    my ($L) = $self->locks;
    my $L_dba = $L && $L->adaptor;
    $self->{adaptor} = $L_dba if $L && !defined $self->{adaptor};
    $L_dba = $self->{adaptor} if defined $self->{adaptor};
    if (@set) {
        my ($dba) = @set;
        throw "Cannot unset adaptor" unless defined $dba;
        throw "Cannot set multiple adaptor" if @set > 1;
        my $SLdba = __dba_to_sldba($dba);
        my $L_dbc = $L_dba && __dbc_str($L_dba->dbc);
        my $new_dbc =         __dbc_str($SLdba->dbc);
        throw "dbc mismatch: have $L_dba ($L_dbc), tried to set $SLdba ($new_dbc)"
          if $L_dba && !__same_dbc($L_dba->dbc, $SLdba->dbc);
        $L_dba = $self->{adaptor} = $SLdba unless $self->{adaptor};
    }
    throw "adaptor not yet available" unless defined $L_dba;
    return $L_dba;
}

sub have_db {
    my ($self) = @_;
    return $self->{adaptor} ? 1 : 0;
}

sub __dba_to_sldba { # hide irregularities in DBAdaptor structure
    my ($dba) = @_;
    return $dba
      if try { $dba->isa('Bio::Vega::DBSQL::SliceLockAdaptor') };

    return $dba->get_SliceLockAdaptor
      if ref($dba) =~ /::DBAdaptor$/; # ugh, but $dba->db is irregular

    return try {
        $dba->db->get_SliceLockAdaptor || die 'nil';
    } catch {
        throw "Cannot get_SliceLockAdaptor from $dba: $_";
    };
}

sub __dbc_str { # wanted: dbc->display_id
    my ($a) = @_;
    my $h = $a->to_hash;
    $h->{'-PASS'} = 'redact' if exists $h->{'-PASS'};
    my @part =
      map { defined $h->{$_} ? "$_='$$h{$_}'" : "$_=undef" }
        sort keys %$h;
    return join ', ', @part;
}

sub __same_dbc {
    my ($a, $b) = @_;
    return ( try { $a->isa('Bio::EnsEMBL::DBSQL::DBConnection') } &&
             try { $b->isa('Bio::EnsEMBL::DBSQL::DBConnection') } &&
             $a->equals($b) );
}


sub author {
    my ($self, @set) = @_;
    my ($L) = $self->locks;
    my $L_a = $L && $L->author;
    $self->{author} = $L_a if $L && !defined $self->{author};
    $L_a = $self->{author} if defined $self->{author};
    if (@set) {
        my ($author) = @set;
        throw "Cannot unset author" unless defined $author;
        throw "Cannot set multiple author" if @set > 1;
        $author = Bio::Vega::Author->new_for_uid() if $author eq 'for_uid';
        # We need the author to have been saved.
        # If we are tied to a database we can do it for the caller.
        if ($author->adaptor) {
            # ensure adaptors match
            $self->adaptor( $author->adaptor );
        } elsif (!$self->have_db) {
            throw 'author must be stored in a database, but broker adaptor is not yet set';
        }
        my $L_a_id = $L_a && $L_a->dbID;
        my $new_id = $self->adaptor->author_dbID(broker_author => $author);
        throw "author mismatch: have #$L_a_id, tried to set #$new_id"
          if $L_a && $L_a_id != $new_id;
        $L_a = $self->{author} = $author;
    }
    throw "author not yet available" unless defined $L_a;
    return $L_a;
}


=head2 locks(@more_locks)

Accessor for L<Bio::Vega::SliceLock> objects.  When adding
@more_locks, L</adaptor> will be used to store any which need it.

Error if the new locks have mismatched adaptor, hostname or author.
Otherwise adds the new locks.

Returns list (or count, in scalar context) of the broker's locks.
These locks will have been C<store>d, but no checking is done for the
read phase of this method: there may be no locks, or the ones returned
may no longer be in the database.

=head2 locks_add_by_dbID(@more_lockid)

Calls L<Bio::Vega::DBSQL::SliceLockAdaptor/fetch_by_dbID> for each id,
then continues as for L</locks>.  Requires L</adaptor> be set.

=cut

sub locks {
    my ($self, @add) = @_;
    @add = @{ $add[0] } # to allow multi-accessor loop in new
      if 1==@add && ref($add[0]) eq 'ARRAY';

    foreach my $new (@add) {
        $self->author( $new->author )
          if !$self->have_db && $new->author->adaptor;
        $self->adaptor->store($new) unless $new->adaptor;
        $self->adaptor( $new->adaptor );
        $self->hostname( $new->hostname );
        $self->author( $new->author ); # possibly redundant (top of loop)
    }
    push @{ $self->{locks} }, @add;
    return @{ $self->{locks} };
}

sub locks_add_by_dbID {
    my ($self, @add) = @_;
    @add = @{ $add[0] } # to allow multi-accessor loop in new
      if 1==@add && ref($add[0]) eq 'ARRAY';

    my $SLdba = $self->adaptor;
    my @lock = map { $SLdba->fetch_by_dbID($_) or
                       die "slice_lock_id=$_ not found" } @add;
    return $self->locks(@lock);
}


=head2 lock_create_for_Slice(%arg)

Create and L<Bio::Vega::DBSQL::SliceLockAdaptor/store> for a given
slice.  Hostname and author must have been set already.

C<%arg> is passed to L<Bio::Vega::DBSQL::SliceLockAdaptor/new>.  Only
the slice (or seq_region_{id,start,end}), intent and otter_version
should be given.

If successful, returns the new lock after adding it to the broker.
The C<do_lock> step will happen later in the broker workflow.

This method does not call SQL C<COMMIT>.

=cut

sub lock_create_for_Slice {
    my ($self, %arg) = @_;
    my @bad = grep { m{dbID|adaptor|active|author|hostname}i } sort keys %arg;
    throw "Args to new should not include (@bad)" if @bad;
    $arg{'-author'} = $self->author;
    $arg{'-hostname'} = $self->hostname;
    $arg{'-otter_version'} = Bio::Otter::Version->version
      unless defined $arg{'-otter_version'};
    my ($prog) = $0 =~ m{(?:^|/)([^/]+)$};
    $arg{'-intent'} = "via $prog"
      unless defined $arg{'-intent'};
    my $new = Bio::Vega::SliceLock->new(%arg);
    $self->locks($new); # will store
    return $new;
}


=head2 lock_create_for_objects($intent, @obj)

Creates locks to cover all the objects.  Currently it makes one per
seq_region, spanning all given objects on it, without consideration
for any other locks.  I<There is room for improvement in a
backwards-compatible way.>

Returns a list of the new locks made, stored and added to broker.

Every C<@obj> must provide the C<feature_Slice> method, the resulting
slice must have a C<seq_region_id> and all must be in the same
database.

For a convenient interface, this method gives no control over the
C<otter_version> of the created locks.

=cut

sub lock_create_for_objects {
    my ($self, $intent, @obj) = @_;
    throw "expected string for intent" if ref($intent) || $intent !~ /\S/;

    my %arg =
      (-author => $self->author,
       -hostname => $self->hostname,
       -otter_version => Bio::Otter::Version->version,
       -intent => $intent);

    # Collect the regions
    my %slice; # key=seq_region_id, value=\@obj_slice
    foreach my $obj (@obj) {
        $self->adaptor($obj->adaptor); # set / assert equivalent
        my $sl = $obj->feature_Slice;
        my $srid = $sl->get_seq_region_id;
        push @{ $slice{$srid} }, $sl;
    }

    # Merge patches of lock, currently in a simplistic way.
    my @out;
    while (my ($srid, $locks) = each %slice) {
        my $min = min(map { $_->start } @$locks);
        my $max = max(map { $_->end   } @$locks);
        my $L = Bio::Vega::SliceLock->new
          (%arg,
           -seq_region_id => $srid,
           -seq_region_start => $min,
           -seq_region_end => $max);
        push @out, $L;
    }

    $self->locks(@out); # will store
    return @out;
}


=head2 exclusive_work($code, $unlock)

Implementation of L<Bio::Vega::DBSQL::SliceLockAdaptor/Workflow>
wrapped up in to operate on the L</locks> given to the broker object.

Will call C<COMMIT> multiple times, via L</adaptor>.

In the case of error it will call C<ROLLBACK>.  Then it will also
L<Bio::EnsEMBL::DBSQL::DBAdaptor/clear_caches>, and attempt to
L<Bio::Vega::DBSQL::SliceLockAdaptor/freshen> each lock to avoid
leaving them in an inconsistent state.  Any part of this tidy-up can
fail.

Will take SliceLocks in the states

=over 4

=item * pre

The call to L<Bio::Vega::DBSQL::SliceLockAdaptor/store> has been made,
so there is an L</adaptor> and L</dbID> - as will be the case for any
lock added to the broker object.

This method calls L<Bio::Vega::DBSQL::SliceLockAdaptor/do_lock> for
you.

Any lock successfully added to the broker will have been stored.

=item * held

Ready to begin an exclusive chunk of work.

=back

and will proceed with the workflow, assuming no errors happen:

=over 4

=item 1. C<COMMIT>

=item 2. all locks reach C<active='held'>

If any cannot be locked, C<ROLLBACK> and error.

=item 3. C<COMMIT>

=item 4. C<bump_activity> on all locks

Also, remember these locks for comparison in L</assert_bumped>.

=item 5. Call $code

Currently with no arguments, ignoring the return value.

This code must not try to modify the state of the locks.

Also the code must not C<COMMIT>.  Instead, call L</exclusive_work>
again.

Rollback is called for you if there is an error.

=item 6. C<COMMIT>

And L<Bio::Vega::DBSQL::DBAdaptor/clear_caches>.

=item 7. If $unlock, then C<unlock> and C<COMMIT> again

=back

Returns nothing if everything was done.  Returns the error message (as
a true value, also sent as a warning) if just the unlock failed.  All
other errors are raised.

=cut

sub _txn_control {
    my ($self, @lock) = @_;
    my $adap = $self->adaptor;
    my $dbh = $adap->dbc->db_handle;

    my $rollback = sub {
        my ($err_ref) = @_;
        chomp $$err_ref;
        try {
            $dbh->rollback;
            $adap->db->clear_caches;
        } catch {
            $$err_ref .= "; then rollback failed: $_";
            chomp $$err_ref;
        };
        foreach my $lock (@lock) {
            try { $adap->freshen($lock) }; # (best effort)
        }
        return;
    };

    my $commit = sub {
        my ($want_txn) = @_;
        $dbh->begin_work if $dbh->{AutoCommit}; # avoid warning
        $dbh->commit;
        $dbh->begin_work if $want_txn;
        return;
    };

    return ($commit, $rollback);
}

our $_pkg_no_recurse; ## no critic (Variables::ProhibitPackageVars)
sub exclusive_work {
    my ($self, $code, $unlock) = @_;

    # Recursion prevention actually needs to be done per $dbh, but
    # global is probably good enough.
    throw "exclusive_work recursion would break transaction control"
      if $_pkg_no_recurse;
    local $_pkg_no_recurse = 1;

    # 1.  Storing the lock has been done already.
    my $adap = $self->adaptor;
    my @lock = $self->locks;
    throw "exclusive_work requires locks" unless @lock;

    my ($commit, $rollback) = $self->_txn_control(@lock);

    # 2.
    $commit->(1); # as up-to-date as we can get
    $adap->freshen($_) foreach @lock;
    my @need_lock = grep { $_->active eq 'pre' } @lock;
    # else active=held and we're OK,
    # or active=free and 3. will make the error.
    foreach my $lock (@need_lock) {
        try {
            $adap->do_lock($lock) or die "lost the race";
        } catch {
            my $err = $_;
            my $what = $lock->describe;
            $rollback->(\$err);
            throw "Cannot proceed, do_lock failed <$err> leaving $what";
        };
    }

    # 3.
    $commit->(1)
      if @need_lock; # else nothing done since last commit
    foreach my $lock (@lock) {
        if (!$lock->is_held_sync) {
            my $what = $lock->describe;
            throw "Cannot proceed, not holding the lock $what";
        }
    }

    # 4.
    my $did_bump = local $self->{_did_bump} = [];
    foreach my $lock (@lock) {
        try {
            $adap->bump_activity($lock);
            push @$did_bump, $lock;
        } catch {
            my $err = $_;
            $rollback->(\$err);
            my $what = $lock->describe('rollback');
            throw "Cannot proceed, lock busy?  error=<$err> on $what";
        };
    }

    ### Got here - we have the region exclusively
    try {
        # 5.
        $code->();
        # 6.
        undef $self->{_did_bump}; # undef now; delete at end of local's scope
        $commit->(0);
        $adap->db->clear_caches;
    } catch {
        my $err = $_;
        $rollback->(\$err);
        my $what = join " || ", map { $_->describe('rollback') } @$did_bump;
        throw "<< $what >> was held, but work failed <$err>";
    };

    # 7.
    if ($unlock) {
        # Unlock could fail, but that is probably less serious
        my $what;
        my $err = try {
            foreach my $lock (@lock) {
                $what = $lock->describe;
                $adap->unlock($lock, $self->author);
            }
            '';
        } catch {
            $_ || "Failed: $_";
        } finally {
            try { $commit->(0) };
        };
        chomp $err if $err;

        if (grep { $_->is_held } @lock) {
            # unlock failed
            warn "Work completed but unlock failed/incomplete.  error=<$err> on $what";
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


=head2 assert_bumped(@slice)

Returns true iff the given slice(s) are all exclusively available to
us.

Error if any of @slice are not contained in a lock which was bumped
during L</exclusive_work>.

Error if called outside L</exclusive_work>.  This method should be
used from the code callback taken by that method.

Caveat: this method will incorrectly return false for any slice which
is covered by adjacent locks.  This could be fixed, but YAGNI.

=cut

sub assert_bumped {
    my ($self, @slice) = @_;
    my $elocks = $self->{_did_bump};
    throw "assert_bumped is only permitted during exclusive_work"
      unless $elocks;
    # @$elocks is independent of $self->locks , so we will not
    # erroneously notice locks added after the bump_activity step
    foreach my $slice (@slice) {
        if (grep { $_->contains_slice($slice) } @$elocks) {
            # ok
        } else {
            my $descr = try { $slice->display_id } catch {"(some slice)"};
            throw "$descr is not (entirely) covered by any of my locks";
        }
    }
    return @slice ? 1 : 0;
}


=head2 foreach_object($code, @obj)

Run C<< $code->($obj) foreach @obj >> inside L</exclusive_work> and
with an L</assert_bumped> check before each one.

Can perform the L</exclusive_work> call for you, and passes on the
return value.

May also be called inside L</exclusive_work>, in which case it returns
nothing.  This form makes bulk unlocking easier.

C<@obj> are presumably the same objects that were given to
L</lock_create_for_objects> earlier.

=cut

sub foreach_object {
    my ($self, $code, @obj) = @_;

    my $do_each = sub {
        foreach my $obj (@obj) {
            $self->assert_bumped($obj->feature_Slice);
            $code->($obj);
        }
    };

    if ($self->{_did_bump}) {
        return $do_each->();
    } else {
        return $self->exclusive_work($do_each);
    }
}


=head2 unlock_all()

Ensure every locks in the broker is C<free>d if possible, then
C<COMMIT> if possible.

It catches all errors, because it is expected to be useful in a "try /
finally" block.  Emits a warning for each error, and returns (purely
FYI) a list of C<[$error, $lock] or [$error]> failure tuples.

Returns nothing for success.

=cut

sub unlock_all {
    my ($self) = @_;
    my @out;
    try {
        my $adap = $self->adaptor;
        my $auth = $self->author;
        my @lock = $self->locks;
        my ($commit, $rollback) = $self->_txn_control(@lock);

        foreach my $lock (@lock) {
            my $dbID = $lock->dbID;
            try {
                $adap->freshen($lock);
                $adap->unlock($lock, $auth)
                  unless $lock->active eq 'free';
            } catch {
                warn "Unlock slice_lock_id=$dbID failed, SliceLock litter remains: $_";
                push @out, [ $_, $lock ];
            };
        }

        $commit->(0);
    } catch {
        push @out, [ $_ ];
    };
    return @out;
}


# Answer initially will be mostly "no"
sub supported {
    my ($called, $dataset) = @_;

    my $db_thing = $dataset->isa('DBI::db') ? $dataset
      : ($dataset->can('get_cached_DBAdaptor')
         ? $dataset->get_cached_DBAdaptor->dbc # B:O:Lace:D
         : $dataset->otter_dba->dbc # B:O:SpeciesDat:D
        );

    return try {
        local $SIG{__WARN__} = sub {
            my ($msg) = @_;
            warn $msg unless $msg =~ /execute failed:/;
            return;
        };
        my $sth = $db_thing->prepare(q{ SELECT * FROM slice_lock LIMIT 1 });
        my $rv = $sth->execute();
        return 0 unless defined $rv; # when RaiseError=0
        my @junk = $sth->fetchrow_array;
        1;
    } catch {
        if (m{(?:^|: )Table '[^']+' doesn't exist($| )}) {
            0;
        } else {
            throw("Unexpected error in supported check: $_");
        }
    };
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
