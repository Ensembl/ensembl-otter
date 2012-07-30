
### Bio::Otter::GappedAlignment::Element::Frameshift

package Bio::Otter::GappedAlignment::Element::Frameshift;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::GapT';

sub type {
    return 'F';
}

sub long_type {
    return 'frameshift';
}
1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Frameshift

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
