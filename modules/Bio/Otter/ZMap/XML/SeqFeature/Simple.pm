
## no critic (Modules::RequireFilenameMatchesPackage)

package Hum::Ace::SeqFeature::Simple;

use strict;
use warnings;

sub zmap_xml_feature_tag {
    my ($self, $offset) = @_;

    $offset ||= 0;

    return sprintf qq{<feature name="%s" start="%d" end="%d" strand="%s" style="%s" score="%.3f"></feature>\n},
        $self->text,
        $offset + $self->seq_start,
        $offset + $self->seq_end,
        $self->seq_strand == -1 ? '-' : '+',
        $self->Method->style_name,
        $self->score;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

