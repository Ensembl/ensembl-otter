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
