package Bio::Vega::SliceLock;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Slice;
use Bio::Vega::ContigLockBroker;

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

Also the L<Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor> performs caching,
which is a complexity to avoid mixing with locks.

=cut

sub FIELDS {
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
        @val{qw{ seq_region_id seq_region_start seq_region_end }} =
          __slice_props($slice);
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

sub __slice_props {
    my ($slice) = @_;
    return ($slice->get_seq_region_id,
            $slice->start, $slice->end);
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
    my ($self, @set) = @_;
    if (@set) {
        # write
        my ($newId) = @set;
        my $oldId = $self->SUPER::dbID();
        throw("dbID is immutable") if defined $oldId;
        return $self->SUPER::dbID($newId);
    } else {
        # read
        return $self->SUPER::dbID();
    }
}

sub adaptor {
    my ($self, @set) = @_;
    if (@set) {
        # write
        my ($newAdap) = @set;
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
      or throw "$self invalid slice (@pos)";
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
                    !try { $newval->isa("Bio::Vega::Author") };
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
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
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

    my $slice = $self->describe_slice;
    my $auth = $self->describe_author;

    return sprintf
      ('SliceLock(%s%s) on %s '.
       'was created %s by %s on host %s to "%s"%s '.
       "last active %s and now %s\n  %s.",
       $dbID ? ('dbID=', $dbID) : ('', 'not stored'), $slice,
       $self->iso8601_ts_begin, $auth, $self->hostname, $self->intent,
       ($rolledback ? ".  Before $rolledback, it was" : ','),
       $self->iso8601_ts_activity, $state, $detail);
}


=head2 describe_slice()

Like C<< $obj->slice->display_id >> but returns text for invalid
slices instead of throwing.

=cut

sub describe_slice {
    my ($self) = @_;
    return try {
        $self->slice->display_id;
    } catch {
        # most likely the slice is invalid
        sprintf("BAD:srID=%s:start=%s:end=%s",
                $self->seq_region_id,
                $self->seq_region_start,
                $self->seq_region_end);
    };
}


=head2 describe_author()

Like C<< $obj->author->email >> but returns text for invalid authors
instead of throwing.

=head2 describe_freed_author()

Like C<< $obj->freed_author->email >> but returns text for invalid
authors instead of throwing.

=cut

sub describe_author {
    my ($self) = @_;
    return try { $self->author->email } catch { "<???>" };
}

sub describe_freed_author {
    my ($self) = @_;
    my $fa = $self->freed_author;
    return undef unless defined $fa;
    return try { $self->freed_author->email } catch { "<???>" };
}

sub _author_id { # internal shortcut
    my ($self) = @_;
    return $self->author->dbID;
}

sub _freed_author_id { # internal shortcut
    my ($self) = @_;
    my $fa = $self->freed_author;
    return defined $fa ? $fa->dbID : undef;
}


sub TO_JSON { # for JSON->new->convert_blessed->encode or direct call
    my ($self) = @_;
    die "TO_JSON of unstored objects is not supported"
      unless (defined $self->dbID &&
              defined $self->_author_id &&
              (!$self->freed_author || defined $self->_freed_author_id));

    my %out;
    my @prop = (# Reconstruction fields
                qw( dbID ),
                qw( seq_region_id seq_region_start seq_region_end ),
                qw( ts_begin ts_activity ts_free ), # unixtimes
                qw( active freed ),                 # enums
                qw( intent hostname otter_version ), # text
                [ author_id => '_author_id' ],
                [ freed_author_id => '_freed_author_id' ],
                # FYI fields
                qw( iso8601_ts_begin iso8601_ts_activity iso8601_ts_free ),
                [ author_email => 'describe_author' ],
                [ freed_author_email => 'describe_freed_author' ]);
    foreach my $prop (@prop) {
        my ($key, $method) = ref($prop) ? @$prop : ($prop, $prop);
        $out{$key} = $self->$method;
    }
    return \%out;
}

# The JSON probably came over plain HTTP, so untrusted
sub new_from_json {
    my ($pkg, @info) = @_;
    my %info = (1 == @info ? %{$info[0]} : @info);
    my %obj;

    my @nonscalar = grep { ref($info{$_}) } keys %info;
    die "Non-scalar incoming properties (@nonscalar)" if @nonscalar;

    delete @info{qw{ iso8601_ts_begin iso8601_ts_activity iso8601_ts_free }};

    # Make approximate author objects
    foreach my $atype (qw( author freed_author )) {
        my $id = delete $info{"${atype}_id"};
        my $email = delete $info{"${atype}_email"};
        if (defined $id) {
            my %auth = (dbID => $id,
                        name => $email,
                        email => $email);
            $info{$atype} = Bio::Vega::Author->new_fast(\%auth);
        }
    }

    my @prop = (qw( dbID ),
                qw( seq_region_id seq_region_start seq_region_end ),
                qw( ts_begin ts_activity ts_free ), # unixtimes
                qw( active freed ),                 # enums
                qw( intent hostname otter_version ), # text
                qw( author freed_author ));
    @obj{@prop} = delete @info{@prop};

    $obj{_unweaken_adaptor} = # 'adaptor' will be weakened, take an extra ref
      $obj{adaptor} = ['BOGUS'];

    my @bad = sort keys %info;
    die "Unrecognised incoming properties (@bad)" if @bad;
    my $self = $pkg->new_fast(\%obj);

    return $self;
}


=head2 contains_slice($cmp_slice, $why_not)

Returns true iff C<$cmp_slice> is directly (i.e. without any
projection or mapping) and entirely within the slice covered by this
lock.

If the optional C<$why_not> is given, it must be an ARRAY ref.
Reasons why the slice is not contained will be pushed onto it.

This checks only the seq_region properties and is independent of
L</is_held>.  Both slices must be stored in the same database.

L<Bio::EnsEMBL::CircularSlice> is not supported and will raise an
error.

=cut

sub contains_slice {
    my ($self, $cmp_slice, $why_not) = @_;
    throw "CircularSlice is not supported" # just because yagni
      if $cmp_slice->is_circular;
    $why_not = [] unless ref($why_not) eq 'ARRAY';

    my $lock_slice = try {
        $self->slice;
    } catch {
        push @$why_not, $_;
        0;
    };

    my $cmp_adap = $cmp_slice->adaptor || 0;
    my $cmp_dbc = $cmp_adap && $cmp_adap->dbc;
    my $lock_dbc = $lock_slice && $lock_slice->adaptor->dbc;

    if ($cmp_dbc && $lock_dbc && $cmp_dbc == $lock_dbc) {
        # stored in same database
        my ($L_srid, $L_start, $L_end) = __slice_props($lock_slice);
        my ($C_srid, $C_start, $C_end) = __slice_props($cmp_slice);
        if ($L_srid == $C_srid) {
            push @$why_not, "not contained, lock($L_start,$L_end) cmp($C_start,$C_end)"
              unless $C_start >= $L_start && $C_end <= $L_end;
        } else {
            push @$why_not, "seq_region_id mismatch, lock $L_srid, cmp $C_srid";
        }
    } else {
        push @$why_not, "dbc mismatch, lock on $lock_dbc, cmp on $cmp_dbc";
    }
#warn join "\n  ", @$why_not if @$why_not;
    return 0 == @$why_not ? 1 : 0;
}


=head1 LEGACY CONTIGLOCK INTERACTION

In order to support old code during the transition to SliceLocks from
ContigLocks, it is possible to use both in the same database.

When the C<contig_lock> table is not present, this does nothing.

Otherwise, old ContigLocks continue to operate as they did before.
The SliceLockAdaptor instructs each SliceLock to create, check or
remove matching ContigLocks to exclude any old code from (at least)
the SliceLock'ed region.

This abuses the C<contig_lock.hostname> field as a composite foreign
key to the C<slice_lock> row.

=cut

# dbc-cached ContigLockBroker->supported flag.
#
# This is a small memory leak, and the code will be removed later.
my %dbc_legacy;
sub _legacy_supported {
    my ($self) = @_;
    my $adap = $self->adaptor
      or throw "ContigLockBroker linkage requires a stored SliceLock";
    my $dbc = $adap->dbc;
    if (!exists $dbc_legacy{"$dbc"}) {
        $dbc_legacy{"$dbc"} =
          Bio::Vega::ContigLockBroker->supported($dbc->db_handle);
    }
    return $dbc_legacy{"$dbc"};
}

# Return a broker (configured with hostname and author) iff
# contig_locks supported.
sub _legacy_contig_broker {
    my ($self) = @_;

    my $broker;
    if ($self->adaptor->{_TESTCODE_no_legacy}) {
        # set during some test cases
    } elsif ($self->_legacy_supported) {
        my $dbID = $self->dbID or throw "need dbID";
        $broker = Bio::Vega::ContigLockBroker->new
          (-author => $self->author,
           -hostname => "SliceLock.$dbID");
    } # else no contig_locks here
    return $broker;
}


=head2 legacy_contig_lock()

To be called by the SliceLockAdaptor.  Obtains locks for overlapping
contigs.  Can cause "lock wait timeout" or other errors.

=cut

sub legacy_contig_lock {
    my ($self) = @_;
    my $broker = $self->_legacy_contig_broker
      or return;

    return $broker->lock_clones_by_slice($self->slice, '', $self->adaptor->db);
}


=head2 legacy_contig_unlock()

To be called by the SliceLockAdaptor.  Removes any related
ContigLocks, returns nothing.

=cut

sub legacy_contig_unlock {
    my ($self) = @_;
    my $broker = $self->_legacy_contig_broker
      or return;

    my $CLdba = $self->adaptor->db->get_ContigLockAdaptor;
    my $locks = $CLdba->list_by_hostname($broker->client_hostname);
    foreach my $lock (@$locks) {
        $CLdba->remove($lock);
    }
    return;
}


__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
