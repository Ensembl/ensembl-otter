
### Bio::Vega::SplicedAlignFeature::DNA

package Bio::Vega::SplicedAlignFeature::DNA;

use strict;
use warnings;

use base qw(
            Bio::Vega::SplicedAlignFeature
            Bio::EnsEMBL::DnaDnaAlignFeature
           );

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    sub _hit_unit   { my ($self, @args) = @_; return $self->Bio::EnsEMBL::DnaDnaAlignFeature::_hit_unit(@args); }
    sub _query_unit { my ($self, @args) = @_; return $self->Bio::EnsEMBL::DnaDnaAlignFeature::_query_unit(@args); }
}

sub _hstrand_or_protein {
    my $self = shift;
    return $self->hstrand // 1;
}

1;

__END__

=head1 NAME - Bio::Vega::SplicedAlignFeature::DNA

=head1 DESCRIPTION

Base class for Bio::Vega::SplicedAlignFeature::DNA and
Bio::Vega::SplicedAlignFeature::Protein.

Extends Bio::EnsEMBL::BaseAlignFeature.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

