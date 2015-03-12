package Bio::Otter::Utils::FeatureSort;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( feature_sort );

# Not a method
#
sub feature_sort {
    my (@unsorted) = @_;
    return unless @unsorted;
    if ($unsorted[0]->can('hseqname')) {
        return sort _feature_cmp_hseqname @unsorted;
    } else {
        return sort _feature_cmp_no_name  @unsorted;
    }
}

# Code duplication for sorting speed
#
sub _feature_cmp_hseqname {
    return
        $a->hseqname cmp $b->hseqname
        ||
        $a->start    <=> $b->start
        ||
        $a->end      <=> $b->end;
}

sub _feature_cmp_no_name {
    return
        $a->start    <=> $b->start
        ||
        $a->end      <=> $b->end;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
