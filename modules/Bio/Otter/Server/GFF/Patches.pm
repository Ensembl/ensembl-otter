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


package Bio::Otter::Server::GFF::Patches;

use strict;
use warnings;
use Try::Tiny;

use base qw( Bio::Otter::Server::GFF );

use Bio::Vega::PatchMapper;

sub get_requested_features {
    my ($self) = @_;

    my $map = $self->make_map;
    my ($cs, $name, $chr, $start, $end, $csver) = @{$map}{qw( cs name chr start end csver )};

    my $chr_slice = $self->get_slice($self->otter_dba, $cs, $name, $chr, $start, $end, $csver);
    my $patch_mapper = Bio::Vega::PatchMapper->new($chr_slice);
    my $features = $patch_mapper->all_features;

    return $features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

