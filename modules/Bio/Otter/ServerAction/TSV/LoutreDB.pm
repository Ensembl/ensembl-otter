package Bio::Otter::ServerAction::TSV::LoutreDB;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction::LoutreDB';

=head1 NAME

Bio::Otter::ServerAction::TSV::LoutreDB - serve requests for info from loutre db, serialised via TSV

=cut

sub serialise_meta {
    my ($self, $results) = @_;

    my $tsv_string = '';

    foreach my $r ( @$results ) {
        $tsv_string .= join("\t", $r->{meta_key}, $r->{meta_value}, $r->{species_id} // '') . "\n";
    }

    return $tsv_string;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
