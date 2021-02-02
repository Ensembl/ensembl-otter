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

package Bio::Otter::Utils::AccessionInfo::Serialise;

use strict;
use warnings;

use Readonly;

use base qw( Exporter );
our @EXPORT_OK = qw(
    fasta_header_column_order
    escape_fasta_description
    unescape_fasta_description
);

=head1 NAME

Bio::Otter::Utils::AccessionInfo::Serialise - definitions and subroutines for serialising AccessionInfo results

=cut

Readonly my @FASTA_HEADER_COLUMN_ORDER => qw(
    acc_sv
    taxon_id
    evi_type
    description
    source
    sequence_length
    currency
);

sub fasta_header_column_order { return @FASTA_HEADER_COLUMN_ORDER; }

{
    my %esc = (
        '|' => '~p',
        '~' => '~t',
        );

    my %unesc = reverse %esc;

    sub escape_fasta_description {
        my ($description) = @_;
        $description =~ s/([|~])/$esc{$1}/g;
        return $description;
    }

    sub unescape_fasta_description {
        my ($description) = @_;
        $description =~ s/(~[pt])/$unesc{$1}/g;
        return $description;
    }
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
