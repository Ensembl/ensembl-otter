package Bio::Otter::Lace::Slice;

use strict;
use warnings;

use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;

sub new {
    my ($pkg, 
        $Client, # object
        $dsname, # e.g. 'human'
        $ssname, # e.g. 'chr20-03'

        $csname, # e.g. 'chromosome'
        $csver,  # e.g. 'Otter'
        $seqname,# e.g. '20'
        $start,  # in the given coordinate system
        $end,    # in the given coordinate system
    ) = @_;

    # chromosome:Otter:chr6-17:2666323:2834369:1


    my $self = {
        '_Client'   => $Client,
        '_dsname'   => $dsname,
        '_ssname'   => $ssname,

        '_csname'   => $csname,
        '_csver'    => $csver  || '',
        '_seqname'  => $seqname,
        '_start'    => $start,
        '_end'      => $end,
    };

    return bless $self, $pkg;
}

sub Client {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change Client" if defined($dummy);

    return $self->{_Client};
}

sub dsname {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change dsname" if defined($dummy);

    return $self->{_dsname};
}

sub ssname {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change ssname" if defined($dummy);

    return $self->{_ssname};
}


sub csname {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change csname" if defined($dummy);

    return $self->{_csname};
}

sub csver {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change csver" if defined($dummy);

    return $self->{_csver};
}

sub seqname {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change seqname" if defined($dummy);

    return $self->{_seqname};
}

sub start {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change start" if defined($dummy);

    return $self->{_start};
}

sub end {
    my ($self, $dummy) = @_;

    die "You shouldn't need to change end" if defined($dummy);

    return $self->{_end};
}

sub length { ## no critic(Subroutines::ProhibitBuiltinHomonyms)
    my ($self) = @_;

    return $self->end() - $self->start() + 1;
}

sub name {
    my ($self) = @_;

    return sprintf "%s_%d-%d",
        $self->ssname,
        $self->start,
        $self->end;
}


sub toHash {
    my ($self) = @_;

    my $hash = {
            'dataset' => $self->dsname(),
            'type'    => $self->ssname(),

            'cs'      => $self->csname(),
            'csver'   => $self->csver(),
            'name'    => $self->seqname(),
            'start'   => $self->start(),
            'end'     => $self->end(),
    };

    return $hash;
}

sub zmap_config_stanza {
    my ($self) = @_;

    my $hash = {
        'dataset'  => $self->dsname,
        'sequence' => $self->ssname,
        'csname'   => $self->csname,
        'csver'    => $self->csver,
        'start'    => $self->start,
        'end'      => $self->end,
    };

    return $hash;
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

