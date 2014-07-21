package Bio::Otter::Lace::OnTheFly::Transcript;

use namespace::autoclean;
use Moose;

use Bio::Otter::Lace::OnTheFly::TargetSeq;
use Bio::Otter::Lace::OnTheFly::Builder::Transcript;
use Bio::Otter::Lace::OnTheFly::Runner::Transcript;

with 'Bio::Otter::Lace::OnTheFly';

has 'vega_transcript' => ( is => 'ro', isa => 'Bio::Vega::Transcript', required => 1 );

sub build_target_seq {
    my $self = shift;

    my $vts = $self->vega_transcript;
    my @names = @{$vts->get_all_Attributes('name')};

    my $hum_seq = Hum::Sequence->new;
    $hum_seq->name($names[0]->value);
    $hum_seq->sequence_string($vts->spliced_seq);

    return Bio::Otter::Lace::OnTheFly::TargetSeq->new( full_seq => $hum_seq );
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
        vega_transcript => $self->vega_transcript,
        );
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
