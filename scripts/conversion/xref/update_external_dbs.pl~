#!/usr/local/bin/perl

=head1 NAME

update_external_dbs.pl - reads external_db entries from reference file

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
    --extdbfile, --extdb=FILE           the path of the file containing
                                        the insert statements of the
                                        entries of the external_db table

=head1 DESCRIPTION

This script reads external_db entries from a file that holds definitions for
all external databases used in Vega. Vega usually reuses a file that is
maintained by Ensembl, which is
ensembl/misc-scripts/external_db/external_dbs.txt.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

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
$support->parse_extra_options('extdbfile|extdb=s');
$support->allowed_params($support->get_common_params, 'extdbfile');

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->check_required_params('extdbfile');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('core');
my $dbh = $dba->dbc->db_handle;

# read external_db entries from the file
$support->log("Reading external_db entries from file...\n");
my $extdbfile = $support->param('extdbfile');
open(IN, '<', "$extdbfile") or $support->throw(
    "Could not open external_db input file $extdbfile for reading: $!");
my @rows;
while (my $row = <IN>) {
	next if ($row =~ /^#/);
    chomp($row);
    my @a = split(/\t/, $row);
	foreach my $col (@a) {
		$col =~ s/\\N//;
	}
    push @rows, {
        'external_db_id'            => $a[0],
        'db_name'                   => $a[1],
        'db_release'                => $a[2],
        'status'                    => $a[3],
        'dbprimary_acc_linkable'    => $a[4],
        'display_label_linkable'    => $a[5],
        'priority'                  => $a[6],
        'db_display_name'           => $a[7],
		'type'                      => $a[8],
		'secondary_db_name'         => $a[9],
		'secondary_db_table'        => $a[10],
    } unless $a[0]=~/^#/;
}
close(IN);
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
            (external_db_id, db_name, db_release, status, dbprimary_acc_linkable, 
            display_label_linkable, priority, db_display_name, type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ');
    foreach my $row (@rows) {
        $sth->execute(
                $row->{'external_db_id'}, 
                $row->{'db_name'},
                $row->{'db_release'},
                $row->{'status'},
                $row->{'dbprimary_acc_linkable'},
                $row->{'display_label_linkable'},
                $row->{'priority'},
                $row->{'db_display_name'},
				$row->{'type'},
        );
    }
    $sth->finish();
    $support->log("Done inserting ".scalar(@rows)." entries.\n");
}

# finish logging
$support->finish_log;

