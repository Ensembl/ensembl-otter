#!/usr/bin/env perl

use strict;
use warnings;

use Bio::Otter::GappedAlignment;

my $src = shift;
open SRC, $src;

my $vulgar_re = qr/^vulgar: /;

while (my $line = <SRC>) {
    chomp $line;
    next unless $line =~ $vulgar_re;

    $line =~ s/$vulgar_re//;
    my $ga = Bio::Otter::GappedAlignment->from_vulgar($line);

    print $ga->reverse_alignment->vulgar_string, "\n";
}

exit 0;
