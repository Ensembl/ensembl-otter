
### Bio::Otter::GappedAlignment::Element::Gap

package Bio::Otter::GappedAlignment::Element::Gap;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::ElementI';

sub type {
    return 'G';
}

sub long_type {
    return 'gap';
}

sub validate {
    my $self = shift;
    ($self->query_length xor $self->target_length) or die "one of query_length or target_length must be 0";
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Gap

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
