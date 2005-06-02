
### Bio::Otter::DnaPepAlignFeature

package Bio::Otter::DnaPepAlignFeature;

use strict;
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

=head1 NAME - Bio::Otter::DnaPepAlignFeature

=head1 DESCRIPTION

Extends its Bio::Otter::DnaPepAlignFeature
baseclass to add the method:

=head1 get_HitDescription

Returns the Bio::Otter::HitDescription object
attached to the feature.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

