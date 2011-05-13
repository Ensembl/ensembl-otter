package Bio::Vega::Utils::Evidence;

# Handy tools for exploring evidence

use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw{
    get_accession_type
    reverse_seq
};

use Bio::Otter::Utils::MM;

# ---- MM based stuff ----

{
    my $mm;

    sub get_accession_type {
        my $name = shift;

        $mm ||= Bio::Otter::Utils::MM->new;

        my $accession_types = $mm->get_accession_types([$name]);
        my $at = $accession_types->{$name};
        if ($at) {
            return @$at;
        } else {
            return ( (undef) x 6 );
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

