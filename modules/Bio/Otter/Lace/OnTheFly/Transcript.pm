=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Lace::OnTheFly::Transcript;

use namespace::autoclean;
use Moose;

use Bio::Otter::Lace::OnTheFly::TargetSeq;
use Bio::Otter::Lace::OnTheFly::Builder::Transcript;
use Bio::Otter::Lace::OnTheFly::Runner::Transcript;
use Bio::Vega::Utils::Attribute qw( get_name_Attribute_value );

with 'Bio::Otter::Lace::OnTheFly';
with 'MooseX::Log::Log4perl';

has 'vega_transcript' => ( is => 'ro', isa => 'Bio::Vega::Transcript', required => 1 );

sub build_target_seq {
    my $self = shift;

    my $vts = $self->vega_transcript;
    my $name = get_name_Attribute_value($vts);

    my $hum_seq = Hum::Sequence->new;
    $hum_seq->name($name);
    $hum_seq->sequence_string($vts->spliced_seq);
    $self->log->debug('target_seq: ', $hum_seq->sequence_string);

    return Bio::Otter::Lace::OnTheFly::TargetSeq->new( full_seq => $hum_seq );
}

sub build_builder {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Builder::Transcript->new(
        @params,
        vega_transcript => $self->vega_transcript,
        );
}

sub build_runner {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Runner::Transcript->new(
        @params,
        resultset_class => 'Bio::Otter::Lace::OnTheFly::ResultSet::GetScript',
        vega_transcript => $self->vega_transcript,
        );
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
