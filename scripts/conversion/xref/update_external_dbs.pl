#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
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

update_external_dbs.pl - reads external_db entries from the ensembl_production database

=head1 SYNOPSIS

update_external_dbs.pl [options]

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

Specific options:


=head1 DESCRIPTION

This script reads external_db entries from the ensembl_production database
The script is called directly from the command line and executed during
vega and ensembl-vega preparation.


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>
Patrick Meidl <meidl@ebi.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use DBI qw( :sql_types );
use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
    $SERVERROOT = "$Bin/../../../..";
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
$support->parse_extra_options(
  'production_host=s',
  'production_port=s',
  'production_user=s',
  'production_pass=s');
$support->allowed_params(
  $support->get_common_params,
  'production_host',
  'production_port',
  'production_user',
  'production_pass');

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('core');
my $dbh = $dba->dbc->db_handle;

# read external_db entries from the file
$support->log("Reading external_db entries from ensembl_production...\n");

my $production_host = $support->param('production_host') || 'ens-staging1';
my $production_port = $support->param('production_port') || 3306;
my $production_user = $support->param('production_user') || 'ensro';
my $production_pass = $support->param('production_pass') || '';

my $production_dsn = sprintf( 'DBI:mysql:ensembl_production:host=%s;port=%d', $production_host, $production_port );
my $production_dbh = DBI->connect( $production_dsn, $production_user, $production_pass, { 'PrintError' => 1 } );
my $production_sth = $production_dbh->prepare('SELECT * FROM external_db');
$production_sth->execute();

my @rows;
while ( my $row = $production_sth->fetchrow_hashref() ) {
  push @rows, {
    'external_db_id'     => $row->{'external_db_id'},
    'db_name'            => $row->{'db_name'},
    'db_release'         => $row->{'db_release'},
    'status'             => $row->{'status'},
    'priority'           => $row->{'priority'},
    'db_display_name'    => $row->{'db_display_name'},
    'type'               => $row->{'type'},
    'secondary_db_name'  => $row->{'secondary_db_name'},
    'secondary_db_table' => $row->{'secondary_db_table'},
    'description'        => $row->{'description'},
  };
}
$production_sth->finish;
$support->log("Done reading ".scalar(@rows)." entries.\n");

# delete all entries from external_db
$support->log("Deleting all entries from external_db...\n");
unless ($support->param('dry_run')) {
  my $num = $dbh->do('DELETE FROM external_db');
  $support->log("Done deleting $num rows.\n");
}

# insert new entries into external_db
$support->log("Inserting new external_db entries into db...\n");
unless ($support->param('dry_run')) {
  my $sth = $dbh->prepare('
        INSERT INTO external_db
            (external_db_id, db_name, db_release, status,
            priority, db_display_name, type, secondary_db_name, secondary_db_table,
            description)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ');
  foreach my $row (@rows) {
    $sth->execute(
      $row->{'external_db_id'},
      $row->{'db_name'},
      $row->{'db_release'},
      $row->{'status'},
      $row->{'priority'},
      $row->{'db_display_name'},
      $row->{'type'},
      $row->{'secondary_db_name'},
      $row->{'secondary_db_table'},
      $row->{'description'},
    );
  }
  $sth->finish();
  $support->log("Done inserting ".scalar(@rows)." entries.\n");
}

# finish logging
$support->finish_log;

