
### Bio::Vega::SplicedAlignFeature::Protein

package Bio::Vega::SplicedAlignFeature::Protein;

use strict;
use warnings;

use base qw(
            Bio::Vega::SplicedAlignFeature
            Bio::EnsEMBL::DnaPepAlignFeature
           );

{
    ## no critic (Subroutines::ProtectPrivateSubs,Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _hit_unit   { my ($self, @args) = @_; return $self->Bio::EnsEMBL::DnaPepAlignFeature::_hit_unit(@args); }
    sub _query_unit { my ($self, @args) = @_; return $self->Bio::EnsEMBL::DnaPepAlignFeature::_query_unit(@args); }

    sub _hstrand_or_protein {
        my $self = shift;
        return '.';
    }

}

1;

__END__

=head1 NAME - Bio::Vega::SplicedAlignFeature::Protein

=head1 DESCRIPTION

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

