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

### Bio::Vega::ServerAnalysis::SolexaIntronFilter

package Bio::Vega::ServerAnalysis::SolexaIntronFilter;

use strict;
use warnings;
use base qw{ Bio::Vega::ServerAnalysis };

my $MAX_PER_INTRON = 10;

sub run {
    my ($self, $features) = @_;

    my $filtered = [];

    my %feats_by_introns;

    # group together features by intron

    for my $af (@$features) {
        my @ugfs = sort { $a->start <=> $b->start } $af->ungapped_features;
        next unless @ugfs > 1;
        my $first_exon = shift @ugfs;
        my $last_exon = pop @ugfs;
        my $intron_string = ($first_exon->end+1).'-';
        for my $f (@ugfs) {
            $intron_string .= ($f->start-1).'_'.($f->end+1).'-';
        }
        $intron_string .= ($last_exon->start-1);
        my $equivs = $feats_by_introns{$intron_string} ||= [];
        push @$equivs, $af; 
    }

    # and only return the best scoring features per intron

    for my $intron (keys %feats_by_introns) {
        my @feats = @{ $feats_by_introns{$intron} };
        if (@feats > $MAX_PER_INTRON) {
            my @sorted = sort { $b->score <=> $a->score } @feats;
            push @$filtered, @sorted[0 .. ($MAX_PER_INTRON-1)];
        }
        else {
            push @$filtered, @feats;
        }
    }

    return $filtered;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

