package Bio::Otter::Lace::OnTheFly::Aligner::Transcript;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Aligner';

has transcript => ( is => 'ro', isa => 'Hum::Ace::SubSeq', required => 1 );

around 'parse' => sub {
    my ($orig, $self, @args) = @_;

    my $basic = $self->$orig(@args);

    if ($self->is_protein) {
        $self->logger->warn('Cannot split protein alignments yet');
    } else {
        foreach my $query ( $basic->query_ids ) {
            my $split = $self->_split_alignment($basic->by_query_id($query));
        }
    }

    return $basic;              # temporary
};

sub _split_alignment {
    my ($self, $gapped_alignment) = @_;
    return $gapped_alignment->split_by_transcript_exons($self->transcript);
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
