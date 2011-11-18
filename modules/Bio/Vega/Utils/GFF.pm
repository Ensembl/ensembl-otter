### Bio::Vega::Utils::GFF

package Bio::Vega::Utils::GFF;

use strict;
use warnings;

sub gff_header {
    my ($name, $start, $end, $dna) = @_;

    # build up a date string in the format specified by the GFF spec

    my ($sec, $min, $hr, $mday, $mon, $year) = localtime;
    $year += 1900;    # correct the year
    $mon++;           # correct the month
    my $date = sprintf "%4d-%02d-%02d", $year, $mon, $mday;

    my $hdr =
        "##gff-version 2\n"
      . "##source-version EnsEMBL2GFF 1.0\n"
      . "##date $date\n"
      . "##sequence-region $name $start $end\n";

    $hdr .= "##DNA\n##$dna\n##end-DNA\n" if $dna;

    return $hdr;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::GFF

=head1 SYNOPSIS

Utilities for creating GFF.

=head1 AUTHOR

Jeremy Henty B<email> jh13@sanger.ac.uk

