package Bio::Otter::Lace::OnTheFly::Runner::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Runner';

has transcript => ( is => 'ro', isa => 'Hum::Ace::SubSeq', required => 1 );

around 'parse' => sub {
    my ($orig, $self, @args) = @_;

    my $result_set = $self->$orig(@args);

    foreach my $query ( $result_set->hit_query_ids ) {
        my $split = $self->_split_alignment($result_set->hit_by_query_id($query));
        $result_set->set_hit_by_query_id($query => [ $split ]);
    }

    return $result_set;
};

sub _split_alignment {
    my ($self, $gapped_alignments) = @_;
    my $ga = $gapped_alignments->[0];

    if (scalar(@{$gapped_alignments}) > 1) {
        $self->log->warn(sprintf("More than one gapped alignment for '%s', using first.", $ga->query_id));
    }

    return $ga->intronify_by_transcript_exons($self->transcript);
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
