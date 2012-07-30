
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

sub cigar_type {
    my $self = shift;
    if ($self->query_length and $self->target_length) {
        return 'M';
    } else {
        return Bio::Otter::GappedAlignment::Element::GapT::cigar_type($self);
    }
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::SplitCodon

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
