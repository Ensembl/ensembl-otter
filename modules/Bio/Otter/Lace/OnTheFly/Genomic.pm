=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
