
### Bio::Otter::DnaPepAlignFeature

package Bio::Otter::DnaPepAlignFeature;

use strict;
use base 'Bio::EnsEMBL::DnaPepAlignFeature';

sub get_HitDescription {
    my( $self ) = @_;
    
    return $self->{'_hit_description'};
}

1;

__END__

=head1 NAME - Bio::Otter::DnaPepAlignFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

