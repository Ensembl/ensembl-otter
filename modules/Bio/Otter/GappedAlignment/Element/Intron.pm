
### Bio::Otter::GappedAlignment::Element::Intron

package Bio::Otter::GappedAlignment::Element::Intron;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::Element::GapT';

sub type {
    return 'I';
}

sub long_type {
    return 'intron';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Intron

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
