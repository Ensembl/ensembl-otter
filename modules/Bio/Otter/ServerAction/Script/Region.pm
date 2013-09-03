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

    my $new_region = $region->new_dissociated_copy;
    $new_region->otter_dba($dba);

    # Removing dbIDs renders EnsEMBL's caches invalid, so clear them if we can.
    $dba->clear_caches if $dba;

    return $new_region;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
