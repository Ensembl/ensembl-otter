
### Bio::Otter::GappedAlignment::Element::NER

package Bio::Otter::GappedAlignment::Element::NER;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::ElementI';

sub type {
    return 'N';
}

sub long_type {
    return 'non-equivalenced region';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::NER

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
