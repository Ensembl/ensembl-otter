package Bio::Otter::Lace::OnTheFly::Genomic;

use namespace::autoclean;
use Moose;

use Bio::Otter::Lace::OnTheFly::TargetSeq;
use Bio::Otter::Lace::OnTheFly::Builder::Genomic;

with 'Bio::Otter::Lace::OnTheFly';

has 'full_seq'      => ( is => 'ro', isa => 'Hum::Sequence', required => 1 );
has 'repeat_masker' => ( is => 'ro', isa => 'CodeRef',       required => 1 );

sub build_target_seq {
    my $self = shift;
    return Bio::Otter::Lace::OnTheFly::TargetSeq->new(
        full_seq        => $self->full_seq,
        repeat_masker   => $self->repeat_masker,
        softmask_target => $self->softmask_target,
        );
}

sub build_builder {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Builder::Genomic->new(
        @params,
        );
}

# FIXME: it would be good to get these from the config.
#
sub logic_names {
    return qw(
        OTF_AdHoc_DNA
        OTF_AdHoc_Protein
        OTF_EST
        OTF_ncRNA
        OTF_mRNA
        OTF_Protein
        );
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
