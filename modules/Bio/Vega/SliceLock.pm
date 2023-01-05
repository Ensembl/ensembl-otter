=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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
                if ($field eq 'otter_version') {
                  $self->{$field} = substr($newval, 0, 16);
                }
                else {
                  $self->{$field} = $newval;
                }
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
      (qq{SliceLock(%s%s) on %s was created %s\n  by %s on host %s\n}.
       qq{  to "%s".\n  %s was last active %s and now %s\n  %s.},
       $dbID ? ('dbID=', $dbID) : ('', 'not stored'), $slice,
       $self->iso8601_ts_begin, $auth, $self->hostname, $self->intent,
       ($rolledback ? "Before $rolledback, it" : 'It'),
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
        if (my $canned = $self->{_clientside_describe_slice}) {
            # on the client, the adaptor is explicitly bogus
            $canned;
        } else {
            # most likely the slice is invalid
            sprintf("BAD:srID=%s:start=%s:end=%s",
                    $self->seq_region_id,
                    $self->seq_region_start,
                    $self->seq_region_end);
        }
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
    # always return one element, in list or scalar context
    return undef unless defined $fa; ## no critic (Subroutines::ProhibitExplicitReturnUndef)
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
                [ slice_name => 'describe_slice' ],
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
    if ($info{slice_name}) {
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
        $obj{_clientside_describe_slice} = delete $info{slice_name};

        $obj{_unweaken_adaptor} = # 'adaptor' will be weakened, take an extra ref
          $obj{adaptor} = ['BOGUS'];

        my @bad = sort keys %info;
        die "Unrecognised incoming properties (@bad)" if @bad;
        my $self = $pkg->new_fast(\%obj);

        return $self;

    }

    # Make author objects
    foreach my $atype (qw( author freedAuthor )) {

        my $id = delete $info{${atype}}{authorId};
        my $email =  delete $info{${atype}}{authorEmail};
        my $name =  delete $info{${atype}}{authorName};

        if (defined $id) {
            my %auth = (dbID => $id,
                        name => $email,
                        email => $name);
            $info{$atype} = Bio::Vega::Author->new_fast(\%auth);
        }
    }

    my @prop =  (qw( dbID seq_region_id seq_region_start seq_region_end ),
                qw( ts_begin ts_activity ts_free ), # unixtimes
                qw( active freed ),                 # enums
                qw( intent ), # text
                qw( author freed_author ));

    my @propDb =(qw( sliceLockId seqRegionId seqRegionStart seqRegionEnd ),
                qw( tsBegin tsActivity tsFree ), # unixtimes
                qw( active freed ),                 # enums
                qw( intent ), # text
                qw( author freedAuthor ));

    @obj{@prop} = delete @info{@propDb};

    $obj{_unweaken_adaptor} = # 'adaptor' will be weakened, take an extra ref
      $obj{adaptor} = ['BOGUS'];

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


__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
