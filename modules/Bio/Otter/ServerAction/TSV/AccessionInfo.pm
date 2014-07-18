package Bio::Otter::ServerAction::TSV::AccessionInfo;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction::AccessionInfo';

=head1 NAME

Bio::Otter::ServerAction::TSV::AccessionInfo - serve requests for accession info, serialised via TSV

=cut

# id_list is CSV for apache scripts.
#
sub deserialise_id_list {
    my ($self, $id_list) = @_;
    return [ split(/,/, $id_list) ];
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
