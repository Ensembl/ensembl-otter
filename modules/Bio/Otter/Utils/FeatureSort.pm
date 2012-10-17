package Bio::Otter::Utils::FeatureSort;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( feature_sort );

# Not a method
#
sub feature_sort {
    my (@unsorted) = @_;
    my @sorted = sort _feature_cmp @unsorted;
    return @sorted;
}

sub _feature_cmp {
    return
        $a->hseqname cmp $b->hseqname
        ||
        $a->start    <=> $b->start
        ||
        $a->end      <=> $b->end;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
