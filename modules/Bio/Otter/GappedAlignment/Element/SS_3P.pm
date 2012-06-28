
### Bio::Otter::GappedAlignment::Element::SS_3P

package Bio::Otter::GappedAlignment::Element::SS_3P;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::GapT';

sub type {
    return '3';
}

sub long_type {
    return "3' splice site";
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::SS_3P

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
