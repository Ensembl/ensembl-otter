=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Otter::Lace::OnTheFly::TargetSeq;

use namespace::autoclean;
use Moose;

with 'MooseX::Log::Log4perl';

has 'full_seq'     => ( is => 'ro', isa => 'Hum::Sequence', required => 1, handles =>[qw( name )] );

has 'start'        => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_start', trigger => \&_too_late );
has 'end'          => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_end',   trigger => \&_too_late );

has 'target_seq'   => ( is => 'ro', isa => 'Hum::Sequence',
                        lazy => 1, builder => '_build_target_seq', init_arg => undef,
                        predicate => '_target_seq_built');

has 'softmask_target' => ( is => 'ro', isa => 'Bool' );
has 'repeat_masker'   => ( is => 'ro', isa => 'CodeRef' );

has 'softmasked_full_seq'   => ( is => 'ro', isa => 'Hum::Sequence',
                                 lazy => 1, builder => '_build_softmasked_full_seq', init_arg => undef );

has 'description_for_fasta' => ( is => 'ro', isa => 'Str', default => 'target' );

sub seqs_for_fasta {
    my $self = shift;
    return $self->target_seq;
}

with 'Bio::Otter::Lace::OnTheFly::FastaFile';

sub all_repeat {
    my $self = shift;
    if ($self->softmask_target) {
        my $sm_dna = $self->target_seq->sequence_string;
        my $has_unmasked = ($sm_dna =~/[ACGT]{5}/);
        return not $has_unmasked;
    }
    return;
}

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
    my ($self, $new, $old) = @_;
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
    my $dna = $target_seq->sequence_string;
    $dna =~ s/-/N/g;            # exonerate doesn't like dashes
    $target_seq->sequence_string($dna);
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
