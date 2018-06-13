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

# Build a contig slice with coordsystem, to attach features to.

package OtterTest::ContigSlice;

use strict;
use warnings;

use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Slice;

sub new {
    my ($pkg) = @_;

    my $ref = "";
    return bless \$ref, $pkg;
}

sub contig_slice {
    my $coord_system = Bio::EnsEMBL::CoordSystem->new(
        -name => 'contig',
        -rank => 3,
        );
    my $ctg_slice = Bio::EnsEMBL::Slice->new(
        -seq_region_name => 'AL359765.6.1.13780',
        -start => 1,
        -end => 13780,
        -strand => 1,
        -coord_system => $coord_system,
    );
    return $ctg_slice;
}

1;
