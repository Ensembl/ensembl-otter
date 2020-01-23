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

package Bio::Vega::Utils::ExonPhase;

use strict;
use warnings;

our @EXPORT_OK;
use parent qw( Exporter );
BEGIN { @EXPORT_OK = qw( exon_phase_EnsEMBL_to_Ace exon_phase_Ace_to_EnsEMBL ); }


=head1 NAME

Bio::Vega::Utils::ExonPhase

=head1 DESCRIPTION

Convert between EnsEMBL and Ace conventions for exon start and end phase.

=cut

my %ens2ace_phase = (
    0   => 1,
    2   => 2,
    1   => 3,
    );

my %ace2ens_phase = (
    1   => 0,
    2   => 2,
    3   => 1,
    );

sub exon_phase_EnsEMBL_to_Ace {
    my ($ens_phase) = @_;
    return $ens2ace_phase{$ens_phase};
}

sub exon_phase_Ace_to_EnsEMBL {
    my ($ace_phase) = @_;
    return $ace2ens_phase{$ace_phase};
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
