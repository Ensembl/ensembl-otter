
package Bio::Otter::Server::GFF::Genes;

use strict;
use warnings;

use base qw( Bio::Otter::Server::GFF );

my @gff_keys = qw(
    gff_source
    gff_seqname
    url_string
    transcript_analyses
    translation_xref_dbs
    );

sub get_requested_features {
    my ($self) = @_;

    my @analysis =
        $self->param('analysis')
        ? split(/,/, $self->param('analysis'))
        : (undef);

    # third parameter of $slice->get_all_Genes() helps
    # preventing lazy-loading of transcripts

    my $map = $self->make_map;
    my $metakey = $self->param('metakey');
    return [
        map {
            @{$self->fetch_mapped_features_ensembl('get_all_Genes', [ $_, undef, 1 ], $map, $metakey)};
        } @analysis ];
}

sub _gff_keys {
    return @gff_keys;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

