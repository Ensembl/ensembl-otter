package Bio::Otter::ServerAction::TSV::FindClones;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction::FindClones';

=head1 NAME

Bio::Otter::ServerAction::TSV::FindClones - server requests to find clones, serialised via TSV

=cut

sub serialise_output {
    my ($self, $results) = @_;

    my $tsv_string = '';
    $tsv_string .= "\tToo many search results, some were omitted - please be more specific\n"
      if $self->result_overflow;

    while (my ($qname, $qname_results) = each %{$results}) {
        while (my ($chr_name, $chr_name_results) = each %{$qname_results}) {
            while (my ($qtype, $qtype_results) = each %{$chr_name_results}) {
                while (my ($components, $count) = each %{$qtype_results}) {
                    $tsv_string .=
                        join("\t", $qname, $qtype, $components, $chr_name)."\n";
                }
            }
        }
    }

    return $tsv_string;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
