package Bio::Otter::Lace::OnTheFly::ResultSet;

use Moose;
use namespace::autoclean;

# Constructor must supply these:
#
has analysis_name => ( is => 'ro', isa => 'Str',   required => 1 );
has is_protein    => ( is => 'ro', isa => 'Bool',  required => 1 );

# Raw results store
#
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
has _hit_by_query_id => (
    traits   => [ 'Hash' ],
    isa      => 'HashRef[ArrayRef[Bio::Otter::GappedAlignment]]',
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        _set_hit_by_query_id => 'set',
        hit_by_query_id      => 'get',
        hit_query_ids        => 'keys',
    },
    );

has aligner => (
    is => 'ro',
    isa => 'Bio::Otter::Lace::OnTheFly::Aligner',
    required => 1,
    handles => [ qw( query_seqs ) ],
    );

has query_seqs_by_name => ( is => 'ro', isa => 'HashRef[Hum::Sequence]',
                            lazy => 1, builder => '_build_query_seqs_by_name', init_arg => undef );

with 'Bio::Otter::Lace::OnTheFly::Format::Ace';
with 'Bio::Otter::Lace::OnTheFly::Format::GFF';
with 'Bio::Otter::Lace::OnTheFly::DBStore';

sub add_hit_by_query_id {
    my ($self, $q_id, $ga) = @_;
    my $hit_by_query_id;
    unless ($hit_by_query_id = $self->hit_by_query_id($q_id)) {
        $hit_by_query_id = $self->_set_hit_by_query_id($q_id => []);
    }
    push @$hit_by_query_id, $ga;
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
