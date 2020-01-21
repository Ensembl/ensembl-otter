=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Lace::OnTheFly::Runner::Transcript;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Runner';

has vega_transcript => ( is => 'ro', isa => 'Bio::Vega::Transcript', required => 1 );

around 'parse' => sub {
    my ($orig, $self, @args) = @_;

    my $result_set = $self->$orig(@args);

    foreach my $query ( $result_set->hit_query_ids ) {
        my $split = $self->_split_alignment($result_set->hit_by_query_id($query));
        $result_set->set_hit_by_query_id($query => [ $split ]);
    }

    return $result_set;
};

sub _split_alignment {
    my ($self, $gapped_alignments) = @_;
    my $ga = $gapped_alignments->[0];

    if (scalar(@{$gapped_alignments}) > 1) {
        $self->log->warn(sprintf("More than one gapped alignment for '%s', using first.", $ga->query_id));
    }

    $ga = $ga->reverse_alignment if $ga->target_strand eq '-';

    return $ga->intronify_by_transcript_exons($self->vega_transcript);
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
