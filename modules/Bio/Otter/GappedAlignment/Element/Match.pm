
### Bio::Otter::GappedAlignment::Element::Match

package Bio::Otter::GappedAlignment::Element::Match;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::MatchT';

sub type {
    return 'M';
}

sub long_type {
    return 'match';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Match

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
