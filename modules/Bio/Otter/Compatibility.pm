package Bio::Otter::Compatibility;

# let's keep here utility functions that should work in both old/new EnsEMBL API
# Author: lg4

use strict;

sub running_headcode {
    my $return_value;
    eval {
        require Bio::EnsEMBL::Slice;
        eval {
            my $fake_slice = bless { 'start'=>1, '_start'=>1 }, 'Bio::EnsEMBL::Slice';
            my $start = $fake_slice->start();
        };
        if($@) {
                # inability to call this method is an indication that
                # either NEW EnsEMBL code is preceded by old EnsEMBL code in the path
                # or is is missing altogether, so we're in the realm of pre-ver20 EnsEMBL
            $return_value = 0;
        } else {
            $return_value = 1;
        }
    };
    if($@) {
        die "There seems to be no EnsEMBL code in the path at all!\n";
    }
    return $return_value;
}

1;

