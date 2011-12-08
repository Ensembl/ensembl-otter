package Bio::Otter::Lace::OnTheFly::Aligner;

use namespace::autoclean;
use Moose;

has type   => ( is => 'ro', isa => 'Str',                                   required => 1 );
has seqs   => ( is => 'ro', isa => 'ArrayRef[Hum::Sequence]',               required => 1 );
has target => ( is => 'ro', isa => 'Bio::Otter::Lace::OnTheFly::TargetSeq', required => 1 );

has fasta_description => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build_fasta_description' );

sub _build_fasta_description {
    my $self = shift;
    return sprintf('query_%s', $self->type);
}

sub fasta_sequences {
    my $self = shift;
    return @{$self->seqs};
}

with 'Bio::Otter::Lace::OnTheFly::FastaFile';

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
