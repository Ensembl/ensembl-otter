
### Bio::Vega::DnaPepAlignFeature

package Bio::Vega::DnaPepAlignFeature;

use strict;
use warnings;
use base 'Bio::EnsEMBL::DnaPepAlignFeature';

sub get_HitDescription {
    my( $self ) = @_;
    
    return $self->{'_hit_description'};
}

sub frame { # has to match the name of the method in Exon.pm
    my( $self ) = @_;
    
    return $self->start() % 3;
}

1;

__END__

=head1 NAME - Bio::Vega::DnaPepAlignFeature

=head1 DESCRIPTION

Extends its Bio::EnsEMBL::DnaPepAlignFeature
baseclass to add the methods:

=head2 get_HitDescription

Returns the Bio::Vega::HitDescription object
attached to the feature.

=head2 frame

<method doc to be completed>

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

