
### Bio::Otter::GappedAlignment::Element::MatchT

package Bio::Otter::GappedAlignment::Element::MatchT;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::ElementI';

sub validate {
    my $self = shift;
    ($self->query_length and $self->target_length) or die "query_length and target_length must be > 0";
    # Shouldn't they also be the same for a match?
    return;
}

sub cigar_type {
    return 'M';
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Match

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
