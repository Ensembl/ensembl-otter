
### Bio::Otter::GappedAlignment::Element::SplitCodon

package Bio::Otter::GappedAlignment::Element::SplitCodon;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::ElementI';

sub type {
    return 'S';
}

sub long_type {
    return 'split codon';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::SplitCodon

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
