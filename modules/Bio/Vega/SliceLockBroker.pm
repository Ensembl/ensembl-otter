package Bio::Vega::SliceLockBroker;

use strict;
use warnings;

use List::MoreUtils 'uniq';
use Try::Tiny;

use Bio::Vega::DBSQL::SliceLockAdaptor;
use Bio::EnsEMBL::Utils::Exception qw ( throw );
use Bio::Otter::Version;


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
There may be none, or the ones returned may be in an inconsistent
state - no checking is done in this method.

=head2 locks_add_by_dbID(@more_lockid)

Calls L<Bio::Vega::DBSQL::SliceLockAdaptor/fetch_by_dbID> for each id,
then continues as for L</locks>.  Requires to know the L</adaptor>.

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
    my @lock = map { $SLdba->fetch_by_dbID($_) } @add;
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
    $self->locks($new); # will store if necessary, or fail
    return $new;
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


=begin sql

-- adaptor like a feature?  a simple_feature or a new thing?

create table slice_lock (
 -- feature-like aspect
 slice_lock_id    int unsigned not null auto_increment,
 seq_region_id    int unsigned not null,
 seq_region_start int unsigned not null,
 seq_region_end   int unsigned not null,
 author_id        int not null,      -- whose it is

 ts_begin         datetime not null, -- when row is INSERTed
 ts_activity      datetime not null, -- when the owner last touched it

 -- Transitions allowed: INSERT -> pre -> free(too_late),
 --   pre -> held -> free(finished | expired | interrupted)
 active           enum('pre', 'held', 'free') not null,
 freed            enum('too_late', 'finished', 'expired', 'interrupted'),
 freed_author_id  int,               -- who ( did / will ) free it

 -- FYI fields
 intent		  varchar(100) not null, -- human readable, some conventions or defaults?
 hostname         varchar(100) not null, -- machine readable
 otter_version    varchar(16),       -- machine readable, where relevant
 ts_free          datetime,          -- when freed was set

 primary key            (slice_lock_id),
 key seq_region_idx     (seq_region_id, seq_region_start),
 key active_author_idx  (active, author_id)
) ENGINE=InnoDB;

=end sql


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
