package Bio::Otter::Lace::OnTheFly::ResultSet;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use Moose;
use namespace::autoclean;

has raw => (
    traits  => [ 'String' ],
    is      => 'rw',
    isa     => 'Str',
    default => q{},
    handles => {
        add_raw_line => 'append',
    },
    );

# This is the main results structure
#
has _by_query_id => (
    traits   => [ 'Hash' ],
    isa      => 'HashRef[ArrayRef[Bio::Otter::GappedAlignment]]',
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        _set_by_query_id => 'set',
        by_query_id      => 'get',
        query_ids        => 'keys',
    },
    );

has aligner => (
    is => 'ro',
    isa => 'Bio::Otter::Lace::OnTheFly::Aligner',
    required => 1,
    handles => {
        analysis_name => 'analysis_name',
        query_seqs    => 'seqs',
        target        => 'target',
        type          => 'type',
    }
    );

has query_seqs_by_name => ( is => 'ro', isa => 'HashRef[Hum::Sequence]',
                            lazy => 1, builder => '_build_query_seqs_by_name', init_arg => undef );

with 'Bio::Otter::Lace::OnTheFly::Ace';

sub add_by_query_id {
    my ($self, $q_id, $ga) = @_;
    my $by_query_id;
    unless ($by_query_id = $self->by_query_id($q_id)) {
        $by_query_id = $self->_set_by_query_id($q_id => []);
    }
    push @$by_query_id, $ga;
    return $ga;
}

sub query_seq_by_name {
    my ($self, $q_id) = @_;
    return $self->query_seqs_by_name->{$q_id};
}

sub _build_query_seqs_by_name { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;

    my %name_seq;
    for my $seq (@{$self->query_seqs}) {
        $name_seq{ $seq->name } = $seq;
    }

    return \%name_seq;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
