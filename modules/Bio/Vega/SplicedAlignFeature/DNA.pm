
### Bio::Vega::SplicedAlignFeature::DNA

package Bio::Vega::SplicedAlignFeature::DNA;

use strict;
use warnings;

use base qw(
            Bio::Vega::SplicedAlignFeature
            Bio::EnsEMBL::DnaDnaAlignFeature
           );

# SUPER works lexically. We need to specify which parent's new we need.
#
sub my_SUPER_new {
    my ($caller, @args) = @_;
    return $caller->Bio::EnsEMBL::DnaDnaAlignFeature::new(@args);
}

{
    ## no critic (Subroutines::ProtectPrivateSubs,Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _hit_unit   { my ($self, @args) = @_; return $self->Bio::EnsEMBL::DnaDnaAlignFeature::_hit_unit(@args); }
    sub _query_unit { my ($self, @args) = @_; return $self->Bio::EnsEMBL::DnaDnaAlignFeature::_query_unit(@args); }

    sub _hstrand_or_protein {
        my $self = shift;
        return $self->hstrand // 1;
    }

    sub _align_feature_class { return 'Bio::EnsEMBL::DnaDnaAlignFeature'; }
    sub _extra_fields        { return qw( pair_dna_align_feature_id ); }
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

