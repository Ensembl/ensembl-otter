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

package Bio::Vega::Utils::Align;

# Handy tools for exploring evidence

use strict;
use warnings;

use Bio::AlignIO;
use Bio::Factory::EMBOSS;

use Bio::Vega::SimpleAlign;

my $factory;

sub new {
    my ($self, %args) = @_;

    $factory ||= Bio::Factory::EMBOSS->new();

    my $comp_app = $factory->program('needle');

    return bless { _comp_app => $comp_app }, $self;
}

sub compare_feature_seqs_to_ref {
    my ($self, $ref_seq, $feature_seqs) = @_;

    my $comp_fh = File::Temp->new();
    my $comp_outfile = $comp_fh->filename;

    $self->{_comp_app}->run({-asequence => $ref_seq,
                             -bsequence => $feature_seqs,
                             -outfile   => $comp_outfile,
                             -aformat   => 'srspair',
                             -aglobal   => 1,
                            });

    my $alnin = Bio::AlignIO->new(-format => 'emboss',
                                  -fh     => $comp_fh);

    my @aln_results;
    while ( my $aln = $alnin->next_aln ) {
        my $bvs_aln = Bio::Vega::SimpleAlign->promote_BioSimpleAlign($aln);
        $bvs_aln->id( $bvs_aln->get_seq_by_pos(2)->id ); # transfer id
        push @aln_results, $bvs_aln;
    }

    return \@aln_results;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

