package Bio::Otter::ServerAction::Script::Region;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction::Region';

=head1 NAME

Bio::Otter::ServerAction::Script::Region - server requests on a region, for use from a script

=cut


### Serialisation & Deserialisation methods

sub deserialise_region {
    my ($self, $region) = @_;

    # The main purpose of this subclass is to ensure that appropriate dissociation from the
    # database occurs before write_region gets its hands on the 'new' region.

    my $dba = $region->otter_dba;

    $region->otter_dba(undef);
    $region->slice->adaptor(undef) if $region->slice;

    # FIXME: this really ought to create a dissociated deep copy of the region, rather than mangle it!

    foreach my $cs ($region->clone_sequences) {
        # FIXME: dissociate clone sequence here
    }

    foreach my $sf ($region->seq_features) {
        # FIXME: dissociate simple feature here
    }

    foreach my $g ($region->genes) {
        $g->dissociate( dissociate_exons => 1 );
    }

    # Removing dbIDs renders EnsEMBL's caches invalid, so clear them if we can.
    $dba->clear_caches if $dba;

    return $region;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
