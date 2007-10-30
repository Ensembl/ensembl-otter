#!/usr/local/bin/perl

=head1 NAME

add_ccds_xrefs.pl - adds xrefs for CCDS identifiers

=head1 SYNOPSIS

add_ccds_xrefs.pl [options]

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
    --ccdsfile FILE                     read input from FILE

=head1 DESCRIPTION

This script adds CCDS identifiers to the database. The input file is a
whitespace-separated list of transcript stable IDs and CCDS identifiers. For
more information on the CCDS database see
http://www.ensembl.org/Homo_sapiens/ccds.html.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHORS

Steve Trevanion <st3@sanger.ac.uk>
Patrick Meidl <pm2@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);
use Data::Dumper;

BEGIN {
    $SERVERROOT = "$Bin/../../../..";
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options('ccdsfile=s');
$support->allowed_params($support->get_common_params, 'ccdsfile');

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# get adaptors
my $dba = $support->get_database('ensembl');
my $ta = $dba->get_TranscriptAdaptor;
my $ea = $dba->get_DBEntryAdaptor;

# get list of identifiers into a hash
$support->check_required_params('ccdsfile');
$support->log_stamped("Reading CCDS identifier input file...\n");
my $ccds_file = $support->param('ccdsfile');
open (FHIN, "<$ccds_file");
my %CCDS_idents;
foreach my $entry (<FHIN>) {
    my ($vega,$ccds) = $entry =~ /(\S*)\s+(\S*)/;
    $CCDS_idents{$vega} = $ccds;
}
$support->log_stamped("Done parsing ".scalar(keys %CCDS_idents)." entries.\n");

# loop over transcripts, updating db with CCDS identifier
$support->log_stamped("Adding xrefs to db...\n");
my ($no_trans, $num_success, $no_match) = (0, 0, 0);
my ($successful, $non_translating, $missing_transcript);
foreach my $k (keys %CCDS_idents) {
    if (my $transcript = $ta->fetch_by_stable_id($k)) {
        if (my $translation = $transcript->translation) {
            $num_success++;
            my $internal_id = $translation->dbID;
            my $ccds_idnt = $CCDS_idents{$k};
            my ($prim_acc) = $ccds_idnt =~ /(\w*)/;
            $successful .= sprintf "    %-30s%-20s%-20s\n", $k, $internal_id, $ccds_idnt;
            my $dbentry = Bio::EnsEMBL::DBEntry->new(
                    -primary_id => $prim_acc,
                    -display_id => $ccds_idnt,
                    -version    => 1,
                    -dbname     => 'CCDS',
                    -release    => 1,
            );
            unless ($support->param('dry_run')) {
                $ea->store($dbentry, $internal_id, 'Translation');
            }
        } else {
            $no_trans++;
            $non_translating .= "    $k\n";
        }
    } else {
        $no_match++;
        $missing_transcript .= "    $k\n";
    }
}
$support->log("Done. ".$support->date_and_mem."\n\n");

# print log results
$support->log("\nProcessed ".scalar(keys %CCDS_idents)." identifiers.\n");
$support->log("OK: $num_success\n");
$support->log("WARNINGS:\n");
$support->log("Identifiers with no matching transcript in Vega: $no_match.\n", 1);
$support->log("Transcripts in this set that don't translate: $no_trans.\n", 1);

if ($successful) {
    $support->log("\nTranscripts which had a CCDS identifier added:\n");
    $support->log(sprintf "    %-30s%-20s%-20s\n", qw(STABLE_ID DBID CCDS_ID));
    $support->log("    " . "-"x70 . "\n");
    $support->log($successful);
}
if ($missing_transcript) {
    $support->log("\nTranscripts with no matching CCDS identifier:\n");
    $support->log($missing_transcript);
}
if ($non_translating) {
    $support->log("\nTranscripts in this set that don't translate:\n");
    $support->log($non_translating);
}

# finish log
$support->finish_log;

