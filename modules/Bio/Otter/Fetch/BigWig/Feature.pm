
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

sub start  { return shift->{start};  }
sub end    { return shift->{end};    }
sub score  { return shift->{score};  }

1;

__END__

=head1 NAME - Bio::Otter::Fetch::BigWig::Feature

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

