#!/usr/local/bin/perl

=head1 NAME

finish_ensembl_vega_db.pl - final adjustments to an Ensembl-vega db
assembly

=head1 SYNOPSIS

finish_ensembl_vega_db.pl [options]

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
    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host
                                        HOST
    --evegaport=PORT                    use ensembl-vega (target) database port
                                        PORT
    --evegauser=USER                    use ensembl-vega (target) database
                                        username USER
    --evegapass=PASS                    use ensembl-vega (target) database
                                        passwort PASS

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

This script does some final adjustments to an Ensembl-vega database. This
includes:

    - deleting data not needed any more (eg dna, repeats)
    - updating seq_region_ids to match those in the core Ensembl db
    - transfer selenocysteines

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
    'evegahost=s',
    'evegaport=s',
    'evegauser=s',
    'evegapass=s',
    'evegadbname=s',
    'ensembldbname=s',
);
$support->allowed_params(
    $support->get_common_params,
    'evegahost',
    'evegaport',
    'evegauser',
    'evegapass',
    'evegadbname',
    'ensembldbname',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# there is nothing to do for a dry run, so exit
if ($support->param('dry_run')) {
    $support->log("Nothing to do for a dry run. Aborting.\n");
    exit;
}

# connect to database and get adaptors
my ($dba, $dbh, $sql, $c);
$dba->{'vega'} = $support->get_database('core');
$dbh->{'vega'} = $dba->{'vega'}->dbc->db_handle;
$dba->{'evega'} = $support->get_database('evega', 'evega');
$dbh->{'evega'} = $dba->{'evega'}->dbc->db_handle;
my $ensembl_db = $support->param('ensembldbname');
my $vega_db = $support->param('dbname');

# delete from assembly, seq_region, coord_system, dna,
# dnac, repeat_consensus, repeat_feature
$support->log_stamped("Deleting assembly...\n");
$sql = qq(DELETE FROM assembly);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c assembly entries.\n\n");

$support->log_stamped("Deleting seq_region...\n");
$sql = qq(DELETE FROM seq_region);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c seq_region entries.\n\n");

$support->log_stamped("Deleting seq_region_attrib...\n");
$sql = qq(DELETE FROM seq_region_attrib);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c seq_region_attrib entries.\n\n");

$support->log_stamped("Deleting coord_system...\n");
$sql = qq(DELETE FROM coord_system);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c coord_system entries.\n\n");

$support->log_stamped("Deleting dna...\n");
$sql = qq(DELETE FROM dna);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c dna entries.\n\n");

$support->log_stamped("Deleting dnac...\n");
$sql = qq(DELETE FROM dnac);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c dnac entries.\n\n");

$support->log_stamped("Deleting repeat_consensus...\n");
$sql = qq(DELETE FROM repeat_consensus);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c repeat_consensus entries.\n\n");

$support->log_stamped("Deleting repeat_feature...\n");
$sql = qq(DELETE FROM repeat_feature);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c repeat_feature entries.\n\n");


# transfer assembly, assembly_exception, seq_region, seq_region_attrib,
# coord_system from Ensembl db
$support->log_stamped("Transfering Ensembl assembly...\n");
$sql = qq(
    INSERT INTO assembly
    SELECT *
    FROM $ensembl_db.assembly
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c assembly entries.\n\n");

$support->log_stamped("Transfering Ensembl assembly_exception...\n");
$sql = qq(
    INSERT INTO assembly_exception
    SELECT *
    FROM $ensembl_db.assembly_exception
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c assembly_exception entries.\n\n");

$support->log_stamped("Transfering Ensembl seq_region...\n");
$sql = qq(
    INSERT INTO seq_region
    SELECT *
    FROM $ensembl_db.seq_region
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c seq_regions.\n\n");

$support->log_stamped("Transfering Ensembl seq_region_attrib...\n");
$sql = qq(
    INSERT INTO seq_region_attrib
    SELECT *
    FROM $ensembl_db.seq_region_attrib
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c seq_region_attrib entries.\n\n");

$support->log_stamped("Transfering Ensembl coord_system...\n");
$sql = qq(
    INSERT INTO coord_system
    SELECT *
    FROM $ensembl_db.coord_system
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c coord_system entries.\n\n");


# determine max(seq_region_id) and max(coord_system_id) in Vega seq_region first
my $sth = $dbh->{'vega'}->prepare("SELECT MAX(seq_region_id) FROM seq_region");
$sth->execute;
my ($max_sri) = $sth->fetchrow_array;
my $sri_adjust = 10**(length($max_sri));
$sth = $dbh->{'vega'}->prepare("SELECT MAX(coord_system_id) FROM seq_region");
$sth->execute;
my ($max_csi) = $sth->fetchrow_array;
my $csi_adjust = 10**(length($max_csi));

# now adjust all seq_region_ids and coord_system_ids
$support->log_stamped("Updating seq_region_ids on all tables:\n");
    # exon
    $support->log_stamped("exon...\n", 1);
    $sql = qq(UPDATE exon SET seq_region_id = seq_region_id-$sri_adjust);
    $c = $dbh->{'evega'}->do($sql);
    # gene
    $support->log_stamped("gene...\n", 1);
    $sql = qq(UPDATE gene SET seq_region_id = seq_region_id-$sri_adjust);
    $c = $dbh->{'evega'}->do($sql);
    # transcript
    $support->log_stamped("transcript...\n", 1);
    $sql = qq(UPDATE transcript SET seq_region_id = seq_region_id-$sri_adjust);
    $c = $dbh->{'evega'}->do($sql);
    # dna_align_feature
    $support->log_stamped("dna_align_feature...\n", 1);
    $sql = qq(UPDATE dna_align_feature SET seq_region_id = seq_region_id-$sri_adjust);
    $c = $dbh->{'evega'}->do($sql);
    # protein_align_feature
    $support->log_stamped("protein_align_feature...\n", 1);
    $sql = qq(UPDATE protein_align_feature SET seq_region_id = seq_region_id-$sri_adjust);
    $c = $dbh->{'evega'}->do($sql);
    
$support->log_stamped("Done.\n\n");

# selenocysteines
$support->log_stamped("Transfering Vega translation_attribs (selenocysteines)...\n");
$sql = qq(
    INSERT INTO translation_attrib
    SELECT tsi2.translation_id, at2.attrib_type_id, ta.value
    FROM
        $vega_db.translation_attrib ta,
        $vega_db.translation_stable_id tsi,
        $vega_db.attrib_type at,
        translation_stable_id tsi2,
        attrib_type at2
    WHERE ta.translation_id = tsi.translation_id
    AND tsi.stable_id = tsi2.stable_id
    AND ta.attrib_type_id = at.attrib_type_id
    AND at.code = at2.code
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c tranlation_attrib entries.\n\n");

# meta
my $mappingstring = 'chromosome:'.$support->param('assembly').'|chromosome:'.$support->param('ensemblassembly');
$support->log_stamped("Removing assembly.mapping $mappingstring from meta table...\n");
$sql = qq(
    DELETE FROM meta
    WHERE meta_key = 'assembly.mapping'
    AND meta_value = '$mappingstring'
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c meta entries.\n\n");

# meta_coord
$support->log_stamped("Adjusting meta_coord...\n");
$sql = qq(
    DELETE FROM meta_coord
    WHERE coord_system_id < $csi_adjust
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c meta_coord entries.\n");
$sql = qq(
    UPDATE meta_coord
    SET coord_system_id = coord_system_id-$csi_adjust
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done adjusting $c meta_coord entries.\n\n");


# finish logfile
$support->finish_log;

