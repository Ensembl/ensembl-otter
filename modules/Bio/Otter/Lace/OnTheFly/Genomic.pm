package Bio::Otter::Lace::OnTheFly::Genomic;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose;

use Bio::Otter::Lace::OnTheFly::TargetSeq;
use Bio::Otter::Lace::OnTheFly::Aligner::Genomic;

with 'Bio::Otter::Lace::OnTheFly';

has 'full_seq' => ( is => 'ro', isa => 'Hum::Sequence', required => 1 );

sub build_target_seq {
    my $self = shift;
    return Bio::Otter::Lace::OnTheFly::TargetSeq->new(
	full_seq => $self->full_seq,
	);
}

sub build_aligner {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Aligner::Genomic->new(
	@params,
	);
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
