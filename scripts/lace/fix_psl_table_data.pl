#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


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
        "DBI:mysql:host=otp2-db;port=3323;database=psl_data",
        ottroot => $passwd,
        { RaiseError => 0, PrintError => 1 }
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

    # Use max size of smallint to mark rows which need update.
    my $max = 2**16 - 1;

    # Populate bin column
    $dbh->do(qq{ UPDATE $table SET bin = $max WHERE bin = 0 });
    my $update = $dbh->prepare(qq{ UPDATE $table SET bin = ? WHERE tName = ? AND tStart = ? AND tEnd = ?});
    while (1) {
        # LIMIT in SQL statement in loop to prevents running out of memory on
        # large tables.
        my $select = $dbh->prepare(qq{ SELECT tName, tStart, tEnd FROM $table WHERE bin = $max LIMIT 10000 });
        $select->execute;
        last unless $select->rows;
        my ($tName, $tStart, $tEnd);
        $select->bind_columns(\$tName, \$tStart, \$tEnd);
        while ($select->fetch) {
            my $bin = smallest_bin_for_range($tStart, $tEnd);
            $update->execute($bin, $tName, $tStart, $tEnd);
        }
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

