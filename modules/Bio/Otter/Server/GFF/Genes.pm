
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

    my @params = ();
    foreach my $param (qw{ cs name type start end metakey csver csver_remote }) {
        my $val = $self->param($param);
        push(@params, defined($val) ? $val : '');
    }

    my @analysis =
        $self->param('analysis')
        ? split(/,/, $self->param('analysis'))
        : (undef);

    # third parameter of $slice->get_all_Genes() helps
    # preventing lazy-loading of transcripts

    return [
        map {
            @{$self->fetch_mapped_features(
                  'gene', 'get_all_Genes', [ $_, undef, 1 ], @params)};
        } @analysis ];
}

sub _gff_keys {
    return @gff_keys;
}

1;

__END__

=head1 AUTHOR

Jeremy Henty B<email> jh13@sanger.ac.uk

