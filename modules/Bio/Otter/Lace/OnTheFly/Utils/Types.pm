package Bio::Otter::Lace::OnTheFly::Utils::Types;

use namespace::autoclean;
use Moose::Util::TypeConstraints;

use Bio::Otter::Lace::OnTheFly::Utils::SeqList;

subtype 'ArrayRefOfHumSeqs'
    => as 'ArrayRef[Hum::Sequence]';

class_type 'SeqListClass'
    => { class => 'Bio::Otter::Lace::OnTheFly::Utils::SeqList' };

coerce 'SeqListClass'
    => from 'ArrayRefOfHumSeqs'
    => via { Bio::Otter::Lace::OnTheFly::Utils::SeqList->new( seqs => $_ ) };

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
