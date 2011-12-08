package Bio::Otter::Lace::OnTheFly;

use namespace::autoclean;
use Moose;

use Bio::Otter::Lace::OnTheFly::Aligner;
use Bio::Otter::Lace::OnTheFly::QueryValidator;
use Bio::Otter::Lace::OnTheFly::TargetSeq;

has 'query_validator' => (
    is      => 'ro',
    isa     => 'Bio::Otter::Lace::OnTheFly::QueryValidator',
    handles => [qw( confirmed_seqs seq_types seqs_for_type seq_by_name )],
    writer  => '_set_query_validator',
    );

has 'target'          => (
    is     => 'ro',
    isa    => 'Bio::Otter::Lace::OnTheFly::TargetSeq',
    handles => {
        target_fasta_file => 'fasta_file',
        target_start      => 'start',
        target_end        => 'end',
        target_seq        => 'target_seq',
        },
    writer => '_set_target',
    );

sub BUILD {
    my ( $self, $params ) = @_;

    $self->_set_query_validator(Bio::Otter::Lace::OnTheFly::QueryValidator->new($params));

    my %target_params = ( full_seq => $params->{target_seq} );
    $target_params{start} = $params->{target_start} if $params->{target_start};
    $target_params{end}   = $params->{target_end} if $params->{target_end};

    $self->_set_target( Bio::Otter::Lace::OnTheFly::TargetSeq->new(\%target_params) );

    return;
}

sub aligners_for_each_type {
    my $self = shift;

    my @aligners;
    foreach my $type ( $self->seq_types ) {
        push @aligners, Bio::Otter::Lace::OnTheFly::Aligner->new(
            type   => $type,
            seqs   => $self->seqs_for_type($type),
            target => $self->target,
            );
    }
    return @aligners;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
