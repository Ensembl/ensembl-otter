package Bio::Otter::Lace::OnTheFly::Aligner;

use namespace::autoclean;
use Moose;

has type         => ( is => 'ro', isa => 'Str',                     required => 1 );
has seqs         => ( is => 'ro', isa => 'ArrayRef[Hum::Sequence]', required => 1 );
has target_fasta => ( is => 'ro', isa => 'File::Temp',              required => 1 );

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
