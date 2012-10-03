package Bio::Otter::Lace::OnTheFly::TargetSeq;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose;

with 'MooseX::Log::Log4perl';

has 'full_seq'     => ( is => 'ro', isa => 'Hum::Sequence', required => 1 );

has 'start'        => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_start', trigger => \&_too_late );
has 'end'          => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_end',   trigger => \&_too_late );

has 'target_seq'   => ( is => 'ro', isa => 'Hum::Sequence',
                        lazy => 1, builder => '_build_target_seq', init_arg => undef,
                        predicate => '_target_seq_built');

has 'softmask_target' => ( is => 'ro', isa => 'Bool' );
has 'repeat_masker'   => ( is => 'ro', isa => 'CodeRef' );

has 'softmasked_full_seq'   => ( is => 'ro', isa => 'Hum::Sequence',
                                 lazy => 1, builder => '_build_softmasked_full_seq', init_arg => undef );

has 'fasta_description' => ( is => 'ro', isa => 'Str', default => 'target' );

sub fasta_sequences {
    my $self = shift;
    return $self->target_seq;
}

with 'Bio::Otter::Lace::OnTheFly::FastaFile';

# could use 'default' for this, but for symmetry with _build_end:
#
sub _build_start {              ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    return 1;
}

sub _build_end {                ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return $self->full_seq->sequence_length;
}

sub _too_late {
    my ($self, $old, $new) = @_;
    if ($self->_target_seq_built) {
        $self->logger->logconfess('Too late to change start or end of TargetSeq');
    }
    return;
}

sub _build_target_seq {         ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $full_seq = $self->softmask_target ? $self->softmasked_full_seq : $self->full_seq;
    my $target_seq = $full_seq->sub_sequence($self->start, $self->end);
    $target_seq->name($full_seq->name);
    return $target_seq;
}

sub _build_softmasked_full_seq { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $um_full_seq = $self->full_seq;
    my $sm_dna_str = uc $um_full_seq->sequence_string;

    # $sm_dna_str captured by closure:
    #
    my $mask_sub = sub {
        my ($start, $end) = @_;

        my $length = $end - $start + 1;
        substr($sm_dna_str, $start - 1, $length,
               lc substr($sm_dna_str, $start - 1, $length));

    };

    &{$self->repeat_masker}($mask_sub);

    my $sm_full_seq = Hum::Sequence::DNA->new;
    $sm_full_seq->name($um_full_seq->name);
    $sm_full_seq->sequence_string($sm_dna_str);

    return $sm_full_seq;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
