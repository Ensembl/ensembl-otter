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

remove_other_xrefs.pl - remove all non Vega xrefs

=head1 SYNOPSIS

remove_other_xrefs.pl [options]

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
    -i, --interactive                   run script interactively (default: true)
    -n, --dry_run, --dry                don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:
    --ensembldbname=NAME                use Ensembl (source) database NAME
    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host HOST
    --evegaport=PORT                    use ensembl-vega (target) database port PORT
    --evegauser=USER                    use ensembl-vega (target) database username USER
    --evegapass=PASS                    use ensembl-vega (target) database password PASS

=head1 DESCRIPTION

This script reoves all non Vega xrefs from an ensembl-vega db. It will probably only ever be used when making a DB for the genebuilders.
The reason for doing it is that these other xrefs can persist through the merge process and can complicate subsequent xref pipeline run by core.


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
use Storable;

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'evegahost=s',
  'evegaport=s',
  'evegauser=s',
  'evegapass=s',
  'evegadbname=s',
);
$support->allowed_params(
  $support->get_common_params,
  'evegahost',
  'evegaport',
  'evegauser',
  'evegapass',
  'evegadbname',
);

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $ev_dba = $support->get_database('evega','evega');
my $ev_dbh = $ev_dba->dbc->db_handle;

#delete
my $cond = qq(not in ('Vega_gene','Vega_transcript','Vega_translation'));
my $num = $ev_dbh->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name $cond));
$support->log("Done deleting $num entries.\n",1);

# object_xrefs
$num = 0;
$support->log("Deleting orphan object_xrefs...\n");
$num = $ev_dbh->do(qq(
           DELETE ox
           FROM object_xref ox
           LEFT JOIN xref x ON ox.xref_id = x.xref_id
           WHERE x.xref_id IS NULL
        ));
  $support->log("Done deleting $num entries.\n",1);

# external_synonyms
$num = 0;
$support->log("Deleting orphan external_synonyms...\n");
$num = $ev_dbh->do(qq(
           DELETE es
           FROM external_synonym es
           LEFT JOIN xref x ON es.xref_id = x.xref_id
           WHERE x.xref_id IS NULL
        ));
$support->log("Done deleting $num entries.\n",1);

$support->log("Resetting gene.display_xref_id...\n");
$num = $ev_dbh->do(qq(
           UPDATE gene g, xref x
           SET g.display_xref_id = x.xref_id
           WHERE g.stable_id = x.dbprimary_acc
        ));
$support->log("Done resetting $num display_xrefs.\n");

$support->finish_log;
