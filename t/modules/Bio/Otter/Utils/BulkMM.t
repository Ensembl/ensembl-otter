#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Otter qw( ^db_or_skipall get_BOSDatasets );
use Bio::Otter::Utils::AccessionInfo;

sub main {
    my ($ds) = get_BOSDatasets('human_test');
    my $pipe_dbh = $ds->pipeline_dba->dbc->db_handle;

    plan tests => 1;
    my $N = 150;
    my $accs = random_accessions
      ($pipe_dbh, $N,
       qw(dna_align_feature protein_align_feature)[int(rand(2))] );
    print "accs = @$accs\n";

    # Set up the drivers to compare
    my @drv = ('Bio::Otter::Utils::BulkMM', 'Bio::Otter::Utils::MM');
    my @ai =
      map { Bio::Otter::Utils::AccessionInfo->new(driver_class => $_) }
        @drv;

    # Fetch.  Can't make timings for both *MM drivers due to caching
    my @fetch = map { $_->get_accession_info($accs) } @ai;

    # Compare.  They're hashrefs, so this is easy.
    is_deeply($fetch[0], $fetch[1], "same")
      ;# or diag explain \@fetch; # may be large

    return 0;
}

# Return arrayref of $N accessions
sub random_accessions {
    my ($dbh, $N, $tbl) = @_;
    my @srid_range = $dbh->selectrow_array
      ("select min(seq_region_id), max(seq_region_id) from $tbl");
    $srid_range[2] = $srid_range[1] - $srid_range[0];

    # gather some until we have enough
    my %srid_used;
    my %out;
    while (keys %out < $N) {
        my $srid = int(rand($srid_range[2])) + $srid_range[0];
        next if $srid_used{$srid} ++;

        my $accs = $dbh->selectcol_arrayref
          ("SELECT hit_name FROM $tbl WHERE seq_region_id = ?", {}, $srid);

        @out{@$accs} = ();
    }

    my $n_del = (keys %out) - $N;
    # drop some at random
    while ($n_del > 0 and my ($k, $v) = each %out) {
        delete $out{$k};
        $n_del --;
    }

    return [ sort keys %out ];
}

exit main();
