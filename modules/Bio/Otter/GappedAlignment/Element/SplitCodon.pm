=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

sub ensembl_cigar_type {
    my $self = shift;
    if ($self->query_length and $self->target_length) {
        return 'M';
    } else {
        return Bio::Otter::GappedAlignment::Element::GapT::ensembl_cigar_type($self);
    }
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::SplitCodon

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
