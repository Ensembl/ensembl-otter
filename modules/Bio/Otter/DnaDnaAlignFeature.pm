
### Bio::Otter::DnaDnaAlignFeature

package Bio::Otter::DnaDnaAlignFeature;

use strict;
use base 'Bio::EnsEMBL::DnaDnaAlignFeature';

sub get_HitDescription {
    my( $self ) = @_;
    
    return $self->{'_hit_description'};
}

1;

__END__

=head1 NAME - Bio::Otter::DnaDnaAlignFeature

=head1 DESCRIPTION

Extends its Bio::Otter::DnaDnaAlignFeature
baseclass to add the method:

=head1 get_HitDescription

Returns the Bio::Otter::HitDescription object
attached to the feature.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

