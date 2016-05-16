#!/usr/bin/env perl

### fix_psl_table_data.pl

use strict;
use warnings;
use DBI;
use Bio::Vega::Utils::UCSC_bins qw{ smallest_bin_for_range };
use Getopt::Long qw{ GetOptions };

{
    my $passwd;
    GetOptions(
        'password=s'    => \$passwd,
    );
    my $dbh = DBI->connect(
        "DBI:mysql:host=mcs17;port=3323;database=psl_data",
        ottroot => $passwd,
        { RaiseError => 1 }
    );
    foreach my $table (get_tables($dbh)) {
        print STDERR "$table\n";
        fix_table($dbh, $table);
    }
}

sub fix_table {
    my ($dbh, $table) = @_;

    # Add bin column
    $dbh->do(qq{ ALTER TABLE $table ADD COLUMN `bin` smallint(5) unsigned NOT NULL FIRST });

    # Populate bin column
    my $update = $dbh->prepare(qq{ UPDATE $table SET bin = ? WHERE tName = ? AND tStart = ? AND tEnd = ?});
    my $select = $dbh->prepare(qq{ SELECT tName, tStart, tEnd FROM $table });
    $select->execute;
    while (my ($tName, $tStart, $tEnd) = $select->fetchrow) {
        my $bin = smallest_bin_for_range($tStart - 1, $tEnd);
        $update->execute($bin, $tName, $tStart, $tEnd);
    }

    # Add bin index
    $dbh->do(qq{ ALTER TABLE $table ADD KEY `tName` (`tName`(14),`bin`) });
}

sub get_tables {
    my ($dbh) = @_;

    my $sth = $dbh->prepare(q{ SHOW TABLES });
    $sth->execute;
    my @tables;
    while (my ($n) = $sth->fetchrow) {
        next if $n =~ /_dna$/;
        push @tables, $n;
    }
    return @tables;
}


__END__

=head1 NAME - fix_psl_table_data.pl

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

