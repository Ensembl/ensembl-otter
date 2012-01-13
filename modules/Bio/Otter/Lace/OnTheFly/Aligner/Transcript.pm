package Bio::Otter::Lace::OnTheFly::Aligner::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Aligner';

has transcript => ( is => 'ro', isa => 'Hum::Ace::SubSeq', required => 1 );

around 'parse' => sub {
    my ($orig, $self, @args) = @_;

    my $basic = $self->$orig(@args);
    my $split = $self->_split_vulgar($basic->{vulgar});

    return $basic->{raw};
};

sub _split_vulgar {
    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
