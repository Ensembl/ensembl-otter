package Bio::Vega::SliceLock;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);

=head1 NAME

Bio::Vega::SliceLock - a lock on part of a seq_region

=head1 DESCRIPTION

This behaves like a read-only feature.  Changes are made through its
broker.

=cut

my @FIELD = qw( seq_region_id seq_region_start seq_region_end
                author ts_begin ts_activity active freed freed_author
                intent hostname ts_free );

sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);

    my %val;
    @val{@FIELD} = rearrange([ map { uc($_) } @FIELD ], @args);

    local $self->{_mutable} = 'new';
    while (my ($field, $val) = each %val) {
        $self->$field($val);
    }

    # When not loaded from DB, there are extra constraints
    my $sla = $self->adaptor;
    $self->_check_fresh unless $sla && $self->dbID && $self->is_stored($sla->db);

    # We don't migrate these between databases.  (Store and stay)
    throw("Cannot instantiate SliceLock with (SliceLockAdaptor xor dbID)")
      if $sla xor $self->dbID;

    return $self;
}

sub _check_fresh {
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
    throw("Fresh SliceLock must have null timestamps, this has [@ts]")
      if grep {defined} @ts;

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


sub is_held {
    my ($self) = @_;
    return $self->active eq 'held' && !$self->freed;
}

sub _init {
    my ($pkg) = @_;
    my %new_method;
    my %author = (author => 1, freed_author => 1);

    # Simple r/w accessors
    foreach my $field (qw( seq_region_id seq_region_start seq_region_end ),
                       qw( ts_begin ts_activity ts_free ), # unixtimes
                       qw( active freed ),        # enums.  database will check
                       qw( author freed_author ), # objects
                       qw( intent hostname )) {   # text
        $new_method{$field} = sub {
            my ($self, $newval) = @_;
            if (@_ > 1) { # qw( freed freed_author ts_free ) are nullable
                # some fields would be safe to mutate and save,
                # but currently we only allow write during new
                throw("$field is immutable") if !$self->{_mutable};
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
            return __iso8601($unixtime);
        };
    }

    while (my ($field, $code) = each %new_method) {
        no strict 'refs';
        *{"$pkg\::$field"} = $code;
    }

    return;
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
