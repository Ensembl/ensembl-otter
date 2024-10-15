=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Vega::SplicedAlignFeature::Protein

package Bio::Vega::SplicedAlignFeature::Protein;

use strict;
use warnings;

use base qw(
            Bio::Vega::SplicedAlignFeature
            Bio::Vega::DnaPepAlignFeature
           );

sub hstrand {
    my ($self, @args) = @_;
    if (@args) {
        my ($hstrand) = @args;
        $self->logger->logcroak("hstrand '$hstrand' not valid for protein") unless $hstrand == 1;
    }
    return $self->SUPER::hstrand(@args);
}

sub _verify_attribs {  ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) called from superclass[0]
    my ($self) = @_;
    $self->SUPER::_verify_attribs;

    my $hstrand = $self->hstrand;
    if (defined $hstrand and $hstrand != 1) {
        $self->logger->logcroak("hstrand '$hstrand' not valid for protein");
    }

    return;
}

# SUPER works lexically. We need to specify which parent's new we need.
#
sub my_SUPER_new {
    my ($caller, @args) = @_;
    return $caller->Bio::Vega::DnaPepAlignFeature::new(@args);
}

sub looks_like_frameshift {
    my ($self, $gap, $hgap) = @_;
    return unless ($gap == 1 or $gap == 2);
    return unless ($hgap == 0 or $hgap == 1);
    return 1;
}

sub looks_like_split_codon {
    my ($self, $gap, $hgap) = @_;
    return ($hgap == 1);
}

{
    ## no critic (Subroutines::ProtectPrivateSubs,Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _hit_unit   { my ($self, @args) = @_; return $self->Bio::Vega::DnaPepAlignFeature::_hit_unit(@args); }
    sub _query_unit { my ($self, @args) = @_; return $self->Bio::Vega::DnaPepAlignFeature::_query_unit(@args); }

    sub _hstrand_or_protein {
        my $self = shift;
        return '.';
    }

    sub _align_feature_class { return 'Bio::Vega::DnaPepAlignFeature'; }
    sub _extra_attribs       { return; }
}

1;

__END__

=head1 NAME - Bio::Vega::SplicedAlignFeature::Protein

=head1 DESCRIPTION

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

