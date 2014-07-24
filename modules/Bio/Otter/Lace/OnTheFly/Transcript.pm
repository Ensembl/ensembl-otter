package Bio::Otter::Lace::OnTheFly::Transcript;

use namespace::autoclean;
use Moose;

use Bio::Otter::Lace::OnTheFly::TargetSeq;
use Bio::Otter::Lace::OnTheFly::Builder::Transcript;
use Bio::Otter::Lace::OnTheFly::Runner::Transcript;

with 'Bio::Otter::Lace::OnTheFly';

has 'vega_transcript' => ( is => 'ro', isa => 'Bio::Vega::Transcript', required => 1 );
has 'transcript'      => ( is => 'ro', isa => 'Hum::Ace::SubSeq', required => 1 );

sub build_target_seq {
    my $self = shift;
    return Bio::Otter::Lace::OnTheFly::TargetSeq->new(
        full_seq => $self->transcript->mRNA_Sequence
        );
}

sub build_builder {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Builder::Transcript->new(
        @params,
        vega_transcript => $self->vega_transcript,
        );
}

sub build_runner {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Runner::Transcript->new(
        @params,
        resultset_class => 'Bio::Otter::Lace::OnTheFly::ResultSet::GetScript',
        transcript      => $self->transcript,
        );
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
