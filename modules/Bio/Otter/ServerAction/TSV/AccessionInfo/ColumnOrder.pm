package Bio::Otter::ServerAction::TSV::AccessionInfo::ColumnOrder;

use strict;
use warnings;

use Readonly;

use base qw( Exporter );
our @EXPORT_OK = qw( accession_info_column_order fasta_header_column_order );

=head1 NAME

Bio::Otter::ServerAction::TSV::AccessionInfo::ColumnOrder - define TSV column order

=cut

Readonly my @ACCESSION_INFO_COLUMN_ORDER => qw(
    name
    evi_type
    acc_sv
    source
    sequence_length
    taxon_list
    description
    currency
    sequence
);

sub accession_info_column_order { return @ACCESSION_INFO_COLUMN_ORDER; }


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


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
