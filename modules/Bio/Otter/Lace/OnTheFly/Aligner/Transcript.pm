package Bio::Otter::Lace::OnTheFly::Aligner::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Aligner';

around 'parse' => sub {
    my ($orig, $self, @args) = @_;
    return $self->$orig(@args);
};

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
