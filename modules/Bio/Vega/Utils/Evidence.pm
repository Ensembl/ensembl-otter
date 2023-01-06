=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

package Bio::Vega::Utils::Evidence;

# Handy tools for exploring evidence

use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw{
    get_accession_type
    reverse_seq
};

use Bio::Otter::Utils::AccessionInfo;

# ---- AccessionInfo based stuff ----

{
    my $ai;

    sub get_accession_type {
        my $name = shift;

        $ai ||= Bio::Otter::Utils::AccessionInfo->new;

        my $accession_types = $ai->get_accession_types([$name]);
        my $at = $accession_types->{$name};
        if ($at) {
            return ($at->{evi_type}, $at->{acc_sv});
        } else {
            return ( (undef) x 2 );
        }
    }
}

# ---- Misc stuff ----

sub reverse_seq {
    my $bio_seq = shift;

    my $rev_seq = $bio_seq->revcom;
    $rev_seq->display_id($bio_seq->display_id . '.rev');

    return $rev_seq;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

