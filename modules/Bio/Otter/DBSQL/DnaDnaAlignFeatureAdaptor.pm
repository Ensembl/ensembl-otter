
### Bio::Otter::DBSQL::DnaDnaAlignFeatureAdaptor

package Bio::Otter::DBSQL::DnaDnaAlignFeatureAdaptor;

use strict;

use Bio::Otter::DnaDnaAlignFeature;
use base 'Bio::EnsEMBL::DBSQL::DnaAlignFeatureAdaptor';


sub _objs_from_sth {
    my $self = shift;
    
    my $hd_aptr = $self->db->get_HitDescriptionAdaptor;
    
    my $features = $self->SUPER::_objs_from_sth(@_);
    
    my $hit_hash = {map {$_->hseqname, undef} @$features};
    $hd_aptr->fetch_HitDescriptions_into_hash($hit_hash);
    foreach my $feat (@$features) {
        if (my $desc = $hit_hash->{$feat->hseqname}) {
            bless $feat, 'Bio::Otter::DnaDnaAlignFeature';
            $feat->{'_hit_description'} = $desc;
        } else {
            warn sprintf "No HitDescription for '%s'", $feat->hseqname;
        }
    }
    return $features;
}


1;

__END__

=head1 NAME - Bio::Otter::DBSQL::DnaDnaAlignFeatureAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

