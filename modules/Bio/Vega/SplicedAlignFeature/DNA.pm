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


### Bio::Vega::SplicedAlignFeature::DNA

package Bio::Vega::SplicedAlignFeature::DNA;

use strict;
use warnings;

use base qw(
            Bio::Vega::SplicedAlignFeature
            Bio::Vega::DnaDnaAlignFeature
           );

# SUPER works lexically. We need to specify which parent's new we need.
#
sub my_SUPER_new {
    my ($caller, @args) = @_;
    return $caller->Bio::Vega::DnaDnaAlignFeature::new(@args);
}

{
    ## no critic (Subroutines::ProtectPrivateSubs,Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _hit_unit   { my ($self, @args) = @_; return $self->Bio::Vega::DnaDnaAlignFeature::_hit_unit(@args); }
    sub _query_unit { my ($self, @args) = @_; return $self->Bio::Vega::DnaDnaAlignFeature::_query_unit(@args); }

    sub _hstrand_or_protein {
        my $self = shift;
        return $self->hstrand // 1;
    }

    sub _align_feature_class { return 'Bio::Vega::DnaDnaAlignFeature'; }
    sub _extra_attribs       { return; } # FIXME: no longer required by DNA nor Protein?
}

1;

__END__

=head1 NAME - Bio::Vega::SplicedAlignFeature::DNA

=head1 DESCRIPTION

Base class for Bio::Vega::SplicedAlignFeature::DNA and
Bio::Vega::SplicedAlignFeature::Protein.

Extends Bio::Vega::BaseAlignFeature.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

