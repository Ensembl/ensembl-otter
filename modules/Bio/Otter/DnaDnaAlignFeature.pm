
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

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

