#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Time::HiRes qw( gettimeofday tv_interval );
use Bio::Otter::Utils::AccessionInfo;

use Test::Otter qw( ^db_or_skipall get_BOSDatasets );


sub main {
    my @drv = ('Bio::Otter::Utils::BulkMM', 'Bio::Otter::Utils::MM');
    plan tests => 2 * @drv - 1; # D timings, D-1 comparisons

    my ($ds) = get_BOSDatasets('human_test');
    my $pipe_dbh = $ds->pipeline_dba->dbc->db_handle;

    my $N = 150;
    # N must be big enough that fetching overheads are not "too high"

    my $t_budget = 45 / 5000;
    # Budget of 45sec per 5k-accession fetch is based on regions I
    # have seen recently.  It may need changing.

    my @acc = map {            # a random set of accessions per driver
        random_accessions
          ($pipe_dbh, $N,
           qw(dna_align_feature protein_align_feature)[int(rand(2))] )
      } @drv;

    # Set up the drivers to compare
    my @ai = map {
        Bio::Otter::Utils::AccessionInfo->new(driver_class => $_);
    } @drv;

    # Fetch the set for each driver, then re-fetch the first set.
    # Can only make timings per driver on disjoint sets, due to caching.
    my (@fetch, @time, @refetch);
    for (my $i=0; $i<@drv; $i++) {
        my $t0 = [ gettimeofday() ];
        $fetch[$i] = $ai[$i]->get_accession_info($acc[$i]);
        $time[$i] = tv_interval($t0);

        $refetch[$i] = $i
          ? $ai[$i]->get_accession_info($acc[0]) : $fetch[0];

        # Compare.  They're hashrefs, so this is easy.
        my $drv = $drv[$i];
        if ($i) {
            is_deeply($refetch[0], $refetch[$i],
                      "$i. refetch[ $drv[0] ] == refetch[ $drv ]")
              ;# or diag explain \@fetch; # may be large
        }

        # Times
        local $TODO = 'times are awry';
        my $t_ea = $time[$i] / $N;
        cmp_ok($t_ea, '<', $t_budget,
               sprintf('%s.  time[ %s ] = %.1fs/%s = %.4fs/ea',
                       $i,       $drv, $time[$i],$N, $t_ea));
    }

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
