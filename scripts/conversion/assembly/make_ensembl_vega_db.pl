#!/usr/local/bin/perl

=head1 NAME

make_ensembl_vega_db.pl - create a db for transfering annotation to the Ensembl
assembly

=head1 SYNOPSIS

make_ensembl_vega_db.pl [options]

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
    --ensembldbname=NAME                use Ensembl (source) database NAME
    --ensemblhost=HOST                  use Ensembl (source) database host HOST
    --ensemblport=PORT                  use Ensembl (source) database port PORT
    --ensembluser=USER                  use Ensembl (source) database username
                                        USER
    --ensemblpass=PASS                  use Ensembl (source) database passwort
                                        PASS
    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host
                                        HOST
    --evegaport=PORT                    use ensembl-vega (target) database port
                                        PORT
    --evegauser=USER                    use ensembl-vega (target) database
                                        username USER
    --evegapass=PASS                    use ensembl-vega (target) database
                                        passwort PASS
    --extdbfile, --extdb=FILE           the path of the file containing
                                        the insert statements of the
                                        entries of the external_db table
    --attribtypefile=FILE               read attribute type definition from FILE

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

It prepares the initial Ensembl schema database to hold Vega annotation on the
Ensembl assembly. Major steps are:

    - create a db with current Ensembl schema
    - transfer Vega chromosomes (with same seq_region_id and name as in
      source db)
    - transfer Ensembl seq_regions, assembly, dna, repeats
    - transfer certain Vega xrefs
    - add coord_system entries
    - transfer Ensembl meta
    - update external_db and attrib_type

=head1 RELATED SCRIPTS

The whole Ensembl-vega database production process is done by these scripts:

    ensembl-otter/scripts/conversion/assembly/make_ensembl_vega_db.pl
    ensembl-otter/scripts/conversion/assembly/align_by_clone_identity.pl
    ensembl-otter/scripts/conversion/assembly/align_nonident_regions.pl
    ensembl-otter/scripts/conversion/assembly/map_annotation.pl
    ensembl-otter/scripts/conversion/assembly/finish_ensembl_vega_db.pl

See documention in the respective script for more information.

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
    unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
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
    'ensemblhost=s',
    'ensemblport=s',
    'ensembluser=s',
    'ensemblpass=s',
    'ensembldbname=s',
    'evegahost=s',
    'evegaport=s',
    'evegauser=s',
    'evegapass=s',
    'evegadbname=s',
);
$support->allowed_params(
    $support->get_common_params,
    'ensemblhost',
    'ensemblport',
    'ensembluser',
    'ensemblpass',
    'ensembldbname',
    'evegahost',
    'evegaport',
    'evegauser',
    'evegapass',
    'evegadbname',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my ($dba, $dbh, $sql);
# Vega (source) database
$dba->{'vega'} = $support->get_database('core');
$dbh->{'vega'} = $dba->{'vega'}->dbc->db_handle;
# Ensembl (source) database
$dba->{'ensembl'} = $support->get_database('ensembl', 'ensembl');
$dbh->{'ensembl'} = $dba->{'ensembl'}->dbc->db_handle;

# create new ensembl-vega (target) database
my $evega_db = $support->param('evegadbname');
$support->log_stamped("Creating ensembl-vega db $evega_db...\n");
if ($support->user_proceed("Would you like to drop the ensembl-vega db $evega_db (if it exists) and create a new one?")) {
    $support->log("Dropping existing ensembl-vega db...\n", 1);
    $dbh->{'vega'}->do("DROP DATABASE IF EXISTS $evega_db") unless ($support->param('dry_run'));
    $support->log("Done.\n", 1);
    $support->log("Creating new ensembl-vega db...\n", 1);
    $dbh->{'vega'}->do("CREATE DATABASE $evega_db") unless ($support->param('dry_run'));
    $support->log("Done.\n", 1);
}
$support->log_stamped("Done.\n\n");

# load schema into ensembl-vega db
$support->log_stamped("Loading schema...\n");
my $schema_file = $SERVERROOT.'/ensembl/sql/table.sql';
$support->log_error("Cannot open $schema_file.\n") unless (-e $schema_file);
my $cmd = "/usr/local/mysql/bin/mysql".
                " -u "  .$support->param('evegauser').
                " -p"   .$support->param('evegapass').
                " -h "  .$support->param('evegahost').
                " -P "  .$support->param('evegaport').
                " "     .$support->param('evegadbname').
                " < $schema_file";
unless ($support->param('dry_run')) {
    system($cmd) == 0 or $support->log_error("Could not load schema: $!");
}
$support->log_stamped("Done.\n\n");

# connect to ensembl-vega database
$dba->{'evega'} = $support->get_database('evega', 'evega');
$dbh->{'evega'} = $dba->{'evega'}->dbc->db_handle;

# transfer chromosome seq_regions from Vega db (with same internal IDs and
# names as in source db)
my $c = 0;
$support->log_stamped("Transfering Vega chromosome seq_regions...\n");
$sql = qq(
    INSERT INTO $evega_db.seq_region
    SELECT sr.*
    FROM seq_region sr, coord_system cs
    WHERE sr.coord_system_id = cs.coord_system_id
    AND cs.name = 'chromosome'
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c seq_regions.\n\n");

# transfer seq_regions from Ensembl db
my $sth;
$support->log_stamped("Transfering Ensembl seq_regions...\n");
# determine max(seq_region_id) and max(coord_system_id) in Vega seq_region first
$sth = $dbh->{'evega'}->prepare("SELECT MAX(seq_region_id) FROM seq_region");
$sth->execute;
my ($max_sri) = $sth->fetchrow_array;
my $sri_adjust = 10**(length($max_sri));
$sth = $dbh->{'evega'}->prepare("SELECT MAX(coord_system_id) FROM seq_region");
$sth->execute;
my ($max_csi) = $sth->fetchrow_array;
my $csi_adjust = 10**(length($max_csi));
# fetch and insert Ensembl seq_regions with adjusted seq_region_id and
# coord_system_id
$sql = qq(
    INSERT INTO $evega_db.seq_region
    SELECT seq_region_id+$sri_adjust, name, coord_system_id+$csi_adjust, length
    FROM seq_region
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c seq_regions.\n\n");

# transfer seq_region_attribs from Ensembl
$support->log_stamped("Transfering Ensembl seq_region_attrib...\n");
$sql = qq(
    INSERT INTO $evega_db.seq_region_attrib
    SELECT sra.seq_region_id+$sri_adjust, sra.attrib_type_id, sra.value
    FROM seq_region_attrib sra, attrib_type at
    WHERE sra.attrib_type_id = at.attrib_type_id
    AND at.code NOT LIKE '\%Count'
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c seq_region_attrib entries.\n\n");

# transfer assembly from Ensembl db
$support->log_stamped("Transfering Ensembl assembly...\n");
$sql = qq(
    INSERT INTO $evega_db.assembly
    SELECT asm_seq_region_id+$sri_adjust, cmp_seq_region_id+$sri_adjust,
           asm_start, asm_end, cmp_start, cmp_end, ori
    FROM assembly
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c assembly entries.\n\n");

# transfer dna from Ensembl db
$support->log_stamped("Transfering Ensembl dna...\n");
$sql = qq(
    INSERT INTO $evega_db.dna
    SELECT seq_region_id+$sri_adjust, sequence
    FROM dna
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c dna entries.\n\n");

# transfer repeat_consensus and repeat_feature from Ensembl db
$support->log_stamped("Transfering Ensembl repeat_consensus...\n");
$sql = qq(
    INSERT INTO $evega_db.repeat_consensus
    SELECT * FROM repeat_consensus
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c repeat_consensus entries.\n");
$support->log_stamped("Transfering Ensembl repeat_feature...\n");
$sql = qq(
    INSERT INTO $evega_db.repeat_feature
    SELECT repeat_feature_id, seq_region_id+$sri_adjust, seq_region_start,
           seq_region_end, seq_region_strand, repeat_start, repeat_end,
           repeat_consensus_id, analysis_id, score
    FROM repeat_feature
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c repeat_feature entries.\n\n");

# transfer xrefs to external_db Vega_gene, Vega_transcript and Vega_translation
# from Vega db
$support->log_stamped("Transfering Vega xrefs (Vega_*)...\n");
$sql = qq(
    INSERT INTO $evega_db.xref
    SELECT x.*
    FROM xref x, external_db ed
    WHERE x.external_db_id = ed.external_db_id
    AND ed.db_name IN
        ('Vega_gene', 'Vega_transcript', 'Vega_translation', 'Interpro');
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c xref entries.\n\n");

# transfer interpro from Vega db
$support->log_stamped("Transfering Vega interpro...\n");
$sql = qq(
    INSERT INTO $evega_db.interpro
    SELECT * FROM interpro
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c interpro entries.\n\n");

# add appropriate entries to coord_system
$support->log_stamped("Adding coord_system entries...\n");
$sql = qq(
    INSERT INTO $evega_db.coord_system
    SELECT coord_system_id, name, version, rank+100, attrib
    FROM coord_system cs
    WHERE cs.name = 'chromosome'
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$sql = qq(
    INSERT INTO $evega_db.coord_system
    SELECT coord_system_id+$csi_adjust, name, version, rank, attrib
    FROM coord_system
);
$c += $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done adding $c coord_system entries.\n\n");

# populate meta_coord
$support->log_stamped("Tranfering meta_coord...\n");
$sql = qq(
    INSERT INTO $evega_db.meta_coord
    SELECT * FROM meta_coord WHERE table_name = 'assembly_exception'
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$sql = qq(
    INSERT INTO $evega_db.meta_coord
    SELECT table_name, coord_system_id+$csi_adjust, max_length
    FROM meta_coord
    WHERE table_name IN ('assembly_exception', 'repeat_feature')
);
$c += $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c meta_coord entries.\n\n");

# populate meta
$support->log_stamped("Tranfering meta...\n");
$sql = qq(
    INSERT IGNORE INTO $evega_db.meta
    SELECT * FROM meta
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c meta entries.\n\n");

# run update_external_dbs.pl
my $options = $support->create_commandline_options({
    'allowed_params' => 1,
    'exclude' => [
        'ensemblhost',
        'ensemblport',
        'ensembluser',
        'ensemblpass',
        'ensembldbname',
        'evegahost',
        'evegaport',
        'evegauser',
        'evegapass',
        'evegadbname',
    ],
    'replace' => {
        dbname      => $support->param('evegadbname'),
        host        => $support->param('evegahost'),
        port        => $support->param('evegaport'),
        user        => $support->param('evegauser'),
        pass        => $support->param('evegapass'),
        logappend   => 1,
    },
});
$support->log_stamped("Updating external_db table...\n");
system("../xref/update_external_dbs.pl $options") == 0
    or $support->throw("Error running update_external_dbs.pl: $!");
$support->log_stamped("Done.\n\n");

# update attributes
$support->log_stamped("Updating attrib_type table...\n");
system("../update_attributes.pl $options") == 0
    or $support->throw("Error running update_attributes.pl: $!");
$support->log_stamped("Done.\n\n");

# finish logfile
$support->finish_log;

