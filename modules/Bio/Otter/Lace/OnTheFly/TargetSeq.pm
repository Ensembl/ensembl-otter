package Bio::Otter::Lace::OnTheFly::TargetSeq;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose;

has 'full_seq'     => ( is => 'ro', isa => 'Hum::Sequence', required => 1 );

has 'start'        => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_start' );
has 'end'          => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_end' );

has 'target_seq'   => ( is => 'ro', isa => 'Hum::Sequence',
                        lazy => 1, builder => '_build_target_seq', init_arg => undef );

has fasta_description => ( is => 'ro', isa => 'Str', default => 'target' );

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

sub _build_target_seq {         ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $target_seq = $self->full_seq->sub_sequence($self->start, $self->end);
    $target_seq->name($self->full_seq->name);
    return $target_seq;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
