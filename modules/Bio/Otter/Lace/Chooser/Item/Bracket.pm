
### Bio::Otter::Lace::Chooser::Item::Bracket

package Bio::Otter::Lace::Chooser::Item::Bracket;

use strict;
use warnings;
use base 'Bio::Otter::Lace::Chooser::Item';

sub is_Bracket {
    return 1;
}

sub string {
    my ($self) = @_;

    return $self->name;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Chooser::Item::Bracket

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

