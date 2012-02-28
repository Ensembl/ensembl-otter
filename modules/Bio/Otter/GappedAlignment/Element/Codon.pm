
### Bio::Otter::GappedAlignment::Element::Codon

package Bio::Otter::GappedAlignment::Element::Codon;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::MatchT';

sub type {
    return 'C';
}

sub long_type {
    return 'codon';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Codon

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
