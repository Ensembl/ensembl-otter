
### Bio::Otter::GappedAlignment::Element::Gap

package Bio::Otter::GappedAlignment::Element::Gap;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::GapT';

sub type {
    return 'G';
}

sub long_type {
    return 'gap';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Gap

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
