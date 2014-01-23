
### Bio::Otter::Fetch::BigWig::Feature

package Bio::Otter::Fetch::BigWig::Feature;

use strict;
use warnings;

sub new {
    my ($pkg, %args) = @_;
    my $new = \ %args;
    bless $new, $pkg;
    return $new;
}

# attributes

sub start {
    my ($self) = @_;
    my $start = $self->{'start'};
    return $start;
}

sub end {
    my ($self) = @_;
    my $end = $self->{'end'};
    return $end;
}

sub score {
    my ($self) = @_;
    my $score = $self->{'score'};
    return $score;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::BigWig::Feature

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

