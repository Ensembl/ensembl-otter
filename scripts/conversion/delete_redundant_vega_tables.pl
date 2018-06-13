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


=head1 NAME

delete_redundant_vega_tables.pl - delete non-ensembl tables from a Vega db

=head1 SYNOPSIS

delete_redundant_vega_tables.pl [options]

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
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

	  --masterhost=HOST                 master schema host
   	  --masterport=PORT                 master schema port
	  --masteruser=USER                 master schema user
	  --masterpass=PASS                 master schema pass
	  --masterdbname=NAME               master schema name

=head1 DESCRIPTION

Use this script to remove all non-ensembl tables from a vega database prior to release.
It will also check that all ensembl tables are indeed present. It does this by comparison
with a master schema database - if this doesn't exist one can easily be created using
/ensembl/sql/table.sql


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

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

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
							  'masterhost=s',
							  'masterport=s',
							  'masteruser=s',
							  'masterpass=s',
							  'masterdbname=s',
							 );
$support->allowed_params($support->get_common_params,
						 'masterhost',
						 'masterport',
						 'masteruser',
						 'masterpass',
						 'masterdbname',
						);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to databases and get adaptors
my $vdba = $support->get_database('ensembl');
my $vdbh = $vdba->dbc->db_handle;
my $mdba = $support->get_database('ensembl','master');
my $mdbh = $mdba->dbc->db_handle;

#get tables from each database and compare
my (%tabs);
map { $_ =~ s/`//g; $tabs{$_} += 1; } $vdbh->tables;
map { $_ =~ s/`//g; $tabs{$_} |= 2; } $mdbh->tables;

my @to_delete = sort grep { $tabs{$_} == 1 } keys %tabs;
my @missing   = sort grep { $tabs{$_} == 2 } keys %tabs;
my @backups   = grep { $_ =~ /backup|bkup/i } keys %tabs;

$\ = "\n";

if (@missing) {
	my $tables = join "\n", @missing;
	$support->log_warning("You have tables missing from your vega database:\n$tables\n");
	unless ($support->user_proceed("The tables are missing:\n$tables\nDo you really want to continue?\n")) {
		exit(0);
	}
}

if (@to_delete ) {
	$support->log("The following tables are not core ensembl tables:\n");
	my $all_tables = join "\n", @to_delete;
	my $bk_tables = join "\n", @backups;
	if ($support->param('dry_run')) {
		$support->log("$all_tables\n\nNothing done for a dry run\n");
		exit;
	}
	if ($support->user_proceed("$all_tables\n\nProceed with deleting all the above non-ensembl databases?\n")) {
		foreach my $t (@to_delete) {
			$vdbh->do("DROP TABLE $t");
		}
	}
	elsif (@backups && $support->user_proceed("$bk_tables\n\nProceed with deleting just the above backups?\n")) {
		foreach my $t (@backups) {
			$vdbh->do("DROP TABLE $t");
		}
	}
	elsif ($support->user_proceed("Go through each table and decide?\n")) {
		foreach my $t (@to_delete) {
			if ($support->user_proceed("\nDelete table $t ?")) {
				$vdbh->do("DROP TABLE $t");
			}
		}
	}
}

$support->finish_log;
