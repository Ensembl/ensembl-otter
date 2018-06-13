=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
