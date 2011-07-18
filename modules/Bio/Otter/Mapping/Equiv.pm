
### Bio::Otter::Mapping::Equiv

package Bio::Otter::Mapping::Equiv;

# This class represents the case where the local assembly is
# equivalent to a remote one and there is no need to map.  An object
# requests features from the remote assembly and passes them to the
# target without mapping the endpoints.

use strict;
use warnings;

sub new {
    my ( $pkg, @args ) = @_;
    my $new = { @args };
    die "missing equivalent chr" unless $new->{-chr};
    return bless $new, $pkg;
}

sub do_features {
    my ( $self, $source, $start, $end, $target ) = @_;
    $target->($_, $_->start, $_->end)
        for @{$source->features($self->{-chr}, $start, $end)};
    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Mapping::Equiv

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

