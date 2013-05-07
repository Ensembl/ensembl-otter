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
