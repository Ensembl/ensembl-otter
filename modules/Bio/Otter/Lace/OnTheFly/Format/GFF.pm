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

package Bio::Otter::Lace::OnTheFly::Format::GFF;

use namespace::autoclean;

# Designed to mix in with Bio::Otter::Lace::OnTheFly::ResultSet
#
use Moose::Role;

with 'MooseX::Log::Log4perl';

use Bio::Otter::Utils::FeatureSort qw( feature_sort );
use Bio::Vega::Utils::EnsEMBL2GFF; # injection of to_gff() into EnsEMBL objects
use Bio::Vega::Utils::GFF;

requires 'analysis_name';
requires 'hit_by_query_id';
requires 'hit_query_ids';

sub gff {
    my ($self, $ensembl_slice) = @_;

    return unless ($self->hit_query_ids);

    my $gff_version = 2;        # FIXME!! is this correct? (see other uses, from DataSet)

    my %gff_args = (
        gff_format        => Bio::Vega::Utils::GFF::gff_format($gff_version),
        gff_source        => $self->analysis_name,
        );

    my $gff = Bio::Vega::Utils::GFF::gff_header($gff_version);

    foreach my $hname (sort $self->hit_query_ids) {

        foreach my $ga (sort {
                $a->target_start <=> $b->target_start
                ||
                $a->query_start  <=> $b->query_start
                        } @{ $self->hit_by_query_id($hname) }) {

            foreach my $fp ( feature_sort $ga->ensembl_features ) {
                $fp->slice($ensembl_slice);
                $gff .= $fp->to_gff(%gff_args);
            }

        }

    }

    return $gff;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
