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

my @tax_info_key_list = qw(
    id
    scientific_name
    common_name
    );

sub _tax_response_line {
    # $_ is the info hashref
    my @value_list = @{$_}{@tax_info_key_list};
    # change undef to '' to avoid warnings
    for (@value_list) { defined $_ or $_ = '' }
    my $response_line = sprintf "%s\n", join "\t", @value_list;
    return $response_line;
}

sub serialise_taxonomy_info {
    my ($self, $results) = @_;

    my $header = sprintf "# %s\n", join "\t", @tax_info_key_list;
    my $response = join '', $header, map { _tax_response_line } @{$results};
    return $response;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
