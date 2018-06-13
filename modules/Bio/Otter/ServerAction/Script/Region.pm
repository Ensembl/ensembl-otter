=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

    my $dba = $region->slice->adaptor->db;

    my $new_region = $region->new_dissociated_copy;
    $new_region->slice->adaptor($dba->get_SliceAdaptor);

    # Removing dbIDs renders EnsEMBL's caches invalid, so clear them if we can.
    $dba->clear_caches if $dba;

    return $new_region;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
