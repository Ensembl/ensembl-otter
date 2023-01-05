#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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


=head1 NAME

trim_align_features.pl - delete unneeded entries from dna/protein_align_feature

=head1 SYNOPSIS

trim_align_features.pl [options]

General options:
    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)

    --dbname, db_name=NAME              use database NAME
    --host, --dbhost, --db_host=HOST    use database host HOST
    --port, --dbport, --db_port=PORT    use database port PORT
    --user, --dbuser, --db_user=USER    use database username USER
    --pass, --dbpass, --db_pass=PASS    use database passwort PASS
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

=head1 DESCRIPTION

This script deletes all data from dna/protein_align_feature that is not needed
for web display. These are all entries with a score < 80 that are not used as
supporting evidence. The reason to do this is to keep database size small and
speed up display.

The script also optimizes some tables, including the repeat and dna tables.


=head1 AUTHOR

Patrick Meidl <pm2@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
    $SERVERROOT = "$Bin/../../..";
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options();
$support->allowed_params($support->get_common_params);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;

# log row counts before trimming
my $sth = $dbh->prepare("SELECT COUNT(*) FROM dna_align_feature");
$sth->execute;
my ($daf_count) = $sth->fetchrow_array;
$sth->finish;
$sth = $dbh->prepare("SELECT COUNT(*) FROM protein_align_feature");
$sth->execute;
my ($paf_count) = $sth->fetchrow_array;
$sth->finish;
$support->log("Feature counts before trimming:\n");
my $fmt1 = "%-25s%15.0f\n";
$support->log(sprintf($fmt1, 'dna_align_feature', $daf_count), 1);
$support->log(sprintf($fmt1, 'protein_align_feature', $paf_count), 1);
$support->log("\n");

if ($support->param('dry_run')) {
    $support->log("Nothing else to be done for dry run. Aborting.\n");
    exit(0);
}

# create temporary tables (daf_tmp, paf_tmp) with entries in daf/paf with score
# < 80 which are used in supporting_feature
$support->log_stamped("Creating temp table daf_tmp for low-scoring transcript_supporting_features...\n");
my $num = $dbh->do(qq(
    CREATE TABLE daf_tmp
    SELECT daf.*
    FROM
        dna_align_feature daf,
        transcript_supporting_feature tsf
    WHERE tsf.feature_type = 'dna_align_feature'
    AND tsf.feature_id = daf.dna_align_feature_id
    AND daf.score < 80
));
$support->log_stamped("Done storing $num entries.\n\n");

$support->log_stamped("Creating temp table paf_tmp for low-scoring transcript_supporting_features...\n");
$num = $dbh->do(qq(
    CREATE TABLE paf_tmp
    SELECT daf.*
    FROM
        protein_align_feature daf,
        transcript_supporting_feature tsf
    WHERE tsf.feature_type = 'protein_align_feature'
    AND tsf.feature_id = daf.protein_align_feature_id
    AND daf.score < 80
));
$support->log_stamped("Done storing $num entries.\n\n");

# delete from daf/paf where score < 80
$support->log_stamped("Deleting from dna_align_feature where score < 80...\n");
$num = $dbh->do(qq(DELETE QUICK FROM dna_align_feature WHERE score < 80));
$support->log_stamped("Done deleting $num entries.\n\n");

$support->log_stamped("Deleting from protein_align_feature where score < 80...\n");
$num = $dbh->do(qq(DELETE QUICK FROM protein_align_feature WHERE score < 80));
$support->log_stamped("Done deleting $num entries.\n\n");

# optimize tables
$support->log_stamped("Optimizing tables...\n");
    $support->log_stamped("dna_align_feature...\n", 1);
    $num = $dbh->do(qq(OPTIMIZE TABLE dna_align_feature));
    $support->log_stamped("protein_align_feature...\n", 1);
    $num = $dbh->do(qq(OPTIMIZE TABLE protein_align_feature));
    $support->log_stamped("repeat_feature...\n", 1);
    $num = $dbh->do(qq(OPTIMIZE TABLE repeat_feature));
    $support->log_stamped("repeat_consensus...\n", 1);
    $num = $dbh->do(qq(OPTIMIZE TABLE repeat_consensus));
    $support->log_stamped("dna...\n", 1);
    $num = $dbh->do(qq(OPTIMIZE TABLE dna));
$support->log_stamped("Done.\n\n");

# copy daf_tmp/paf_tmp back into daf/paf
$support->log_stamped("Copying data back from daf_tmp into dna_align_feature...\n");
$num = $dbh->do(qq(INSERT ignore INTO dna_align_feature SELECT * FROM daf_tmp));
$support->log_stamped("Done inserting $num rows.\n\n");

$support->log_stamped("Copying data back from paf_tmp into protein_align_feature...\n");
$num = $dbh->do(qq(INSERT ignore INTO protein_align_feature SELECT * FROM paf_tmp));
$support->log_stamped("Done inserting $num rows.\n\n");

# drop temporary tables
#if ($support->user_proceed("Would you like to drop the temporary tables daf_tmp and paf_tmp?")) {
#    $support->log_stamped("Dropping daf_tmp...\n");
#    $dbh->do(qq(DROP TABLE daf_tmp));
#    $support->log_stamped("Done.\n\n");
#    $support->log_stamped("Dropping paf_tmp...\n");
#    $dbh->do(qq(DROP TABLE paf_tmp));
#    $support->log_stamped("Done.\n\n");
#}

# log row counts after trimming
$sth = $dbh->prepare("SELECT COUNT(*) FROM dna_align_feature");
$sth->execute;
($daf_count) = $sth->fetchrow_array;
$sth->finish;
$sth = $dbh->prepare("SELECT COUNT(*) FROM protein_align_feature");
$sth->execute;
($paf_count) = $sth->fetchrow_array;
$sth->finish;
$support->log("Feature counts after trimming:\n");
$support->log(sprintf($fmt1, 'dna_align_feature', $daf_count), 1);
$support->log(sprintf($fmt1, 'protein_align_feature', $paf_count), 1);
$support->log("\n");

# finish log_stampedfile
$support->finish_log;

