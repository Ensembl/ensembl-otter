package Bio::Vega::Utils::Evidence;

# Handy tools for exploring evidence

use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw{
    get_accession_type
};

use Bio::Otter::Utils::MM;

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

1;
