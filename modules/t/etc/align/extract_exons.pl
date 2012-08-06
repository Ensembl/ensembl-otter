#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

my ($clone_fn, $query_fn, $transcript_fn, $spec_fn, $exon_base);

my $opt_ok = GetOptions(
    'clone=s'      => \$clone_fn,
    'query=s'      => \$query_fn,
    'transcript=s' => \$transcript_fn,
    'spec=s'       => \$spec_fn,
    'exon_base=s'  => \$exon_base,
    );
die 'Bad options' unless $opt_ok;

my $spec_file;
open $spec_file, $spec_fn;

my @coords;

while (my $line = <$spec_file>) {
    chomp $line;
    next if $line =~ /^#/;

    my ($name, $q_start, $q_end, $t_start, $t_end) = split "\t", $line;
    my ($n) = $name =~ /(\d+)/;
    my $e_db   = sprintf('%s.%d', $exon_base, $n);
    my $e_name = sprintf('%s.fa', $e_db);
    print "$name:\t$q_start\t-\t$q_end\t$t_start\t-\t$t_end => $e_name\n";

    my $e_spec = join('..', $q_start, $q_end);

    system 'extractseq', '-auto', $query_fn, $e_name, '-regions', $e_spec, '-osdbname', $e_db;

    push @coords, [$t_start, $t_end];
}

my $spec = join(',', map { join('..', @$_) } @coords);
print "Spec: $spec\n";

system 'extractseq', '-auto', $clone_fn, $transcript_fn, '-regions', $spec;

exit 0;
