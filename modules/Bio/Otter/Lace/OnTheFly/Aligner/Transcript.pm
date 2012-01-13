package Bio::Otter::Lace::OnTheFly::Aligner::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Aligner';

has transcript => ( is => 'ro', isa => 'Hum::Ace::SubSeq', required => 1 );

around 'parse' => sub {
    my ($orig, $self, @args) = @_;

    my $basic = $self->$orig(@args);
    # FIXME: objectification required
    foreach my $query ( keys %{$basic->{by_query_id}} ) {
        my $split = $self->_split_vulgar($basic->{by_query_id}->{$query});
    }

    return $basic->{raw};
};

sub _split_vulgar {
    my ($self, $basic) = @_;

    my $transcript = $self->transcript;
    if ($transcript->strand == -1) {
        warn "Can't handle reverse strand transcript yet";
        return;
    }

    print "Considering transcript ", $transcript->start, " - ", $transcript->end, "\n";

    my @exons = $transcript->get_all_Exons;
    my @vulgar = ( @{$basic->{vulgar}} ); # make a copy we can consume

    return unless @vulgar;

    my @split;

    my $vulgar_comp = shift @vulgar;
    my $tsplice_curr = $basic->{t_start}; # current spliced target pos

    EXON: foreach my $exon (@exons) {
        my @exon_vulgar;
        print "Considering exon ", $exon->start, " - ", $exon->end, "\n";
    }

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
