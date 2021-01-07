=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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


### Bio::Otter::GappedAlignment::Element::GapT

package Bio::Otter::GappedAlignment::Element::GapT;

use strict;
use warnings;

use base 'Bio::Otter::GappedAlignment::ElementI';

sub cigar_type {
    my $self = shift;
    if ($self->target_length) {
        return 'D';
    } elsif ($self->query_length) {
        return 'I';
    } else {
        $self->logger->logconfess('Neither of target_length and query_length is non-zero');
        return;
    }
}

# At least as far as we're concerned, ensembl do things the wrong way round
#
sub ensembl_cigar_type {
    my $self = shift;
    my $ct = $self->cigar_type;
    return $ct eq 'D' ? 'I' : 'D'; # swap D's and I's
}

sub validate {
    my $self = shift;
    ($self->query_length xor $self->target_length)
        or $self->logger->logconfess("one of query_length or target_length must be 0");
    return;
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element::Match

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
