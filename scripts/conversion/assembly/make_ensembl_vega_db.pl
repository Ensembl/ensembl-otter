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

    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host HOST
    --evegaport=PORT                    use ensembl-vega (target) database port PORT
    --evegauser=USER                    use ensembl-vega (target) database username USER
    --evegapass=PASS                    use ensembl-vega (target) database password PASS
    --ensembldbname=NAME                use Ensembl (source) database NAME
    --ensemblhost=HOST                  use Ensembl (source) database host HOST
    --ensemblport=PORT                  use Ensembl (source) database port PORT
    --ensembluser=USER                  use Ensembl (source) database username USER
    --ensemblpass=PASS                  use Ensembl (source) database password PASS

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

    - optionally remove preexisting assembly mappings from Ensembl (they will be kept in non-ineractive mode)
        they should be left in ensembl-vega for consistency with other e! dbs
    - create a db with current Ensembl schema
    - transfer Vega chromosomes (with same seq_region_id and name as in
      source db)
    - transfer Ensembl seq_regions, assembly, dna, repeats
    - transfer assembly mappings from Vega
    - transfer certain Vega xrefs
    - add coord_system entries
    - transfer Ensembl meta
    - update external_db and attrib_type

=head1 RELATED SCRIPTS

The whole Ensembl-vega database production process is done by these scripts:

    ensembl-otter/scripts/conversion/assembly/make_ensembl_vega_db.pl
    ensembl-otter/scripts/conversion/assembly/map_annotation.pl
    ensembl-otter/scripts/conversion/assembly/finish_ensembl_vega_db.pl

See documention in the respective script for more information.


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
  'ensemblhost=s',
  'ensemblport=s',
  'ensembluser=s',
  'ensemblpass=s',
  'ensembldbname=s',
  'ensemblassembly=s',
  'evegahost=s',
  'evegaport=s',
  'evegauser=s',
  'evegapass=s',
  'evegadbname=s',
  'assembly=s',
);
$support->allowed_params(
  $support->get_common_params,
  'ensemblhost',
  'ensemblport',
  'ensembluser',
  'ensemblpass',
  'ensembldbname',
  'ensemblassembly',
  'evegahost',
  'evegaport',
  'evegauser',
  'evegapass',
  'evegadbname',
  'assembly',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# check location of databases
unless ($support->param('ensemblhost') eq $support->param('evegahost') && $support->param('ensemblport') eq $support->param('evegaport')) {
  $support->log_error("Databases must be on the same mysql instance\n");
}

# connect to database and get adaptors
my ($dba, $dbh, $sql);
# Vega (source) database
$dba->{'vega'} = $support->get_database('core');
$dbh->{'vega'} = $dba->{'vega'}->dbc->db_handle;
# Ensembl (source) database
$dba->{'ensembl'} = $support->get_database('ensembl', 'ensembl');
$dbh->{'ensembl'} = $dba->{'ensembl'}->dbc->db_handle;

my $params = {
    'allowed_params' => 1,
    'exclude' => [
      'assembly',
      'ensemblhost',
      'ensemblport',
      'ensembluser',
      'ensemblpass',
      'ensembldbname',
      'ensemblassembly',
      'evegahost',
      'evegaport',
      'evegauser',
      'evegapass',
      'evegadbname',
      'assembly',
    ],
    'replace' => {
      logfile     => 'make_ensembl_vega_update_attributes_vega.log',
      interactive => 0,
    },
  };

##update external_db and attrib tables in vega and ensembl-vega database
if ( (! $support->param('dry_run'))
       && $support->user_proceed("Would you like to update the attrib_type tables for the ensembl and vega databases?\n")) {

  #update vega database
  my $options = $support->create_commandline_options($params);
  $support->log_stamped("Updating attrib_type table for ".$support->param('dbname')."...\n");
  eval {
    system("$Bin/../update_attributes.pl $options") == 0
      or $support->throw("Error running update_attributes.pl: $!");
    $support->log_stamped("Done.\n\n");
  };

  #update ensembl database
  $params->{'replace'}{'logfile'} = 'make_ensembl_vega_update_attributes_ens.log';
  $params->{'replace'}{'dbname'}  = $support->param('ensembldbname');
  $options = $support->create_commandline_options($params);
  $support->log_stamped("Updating attrib_type table for ".$support->param('ensembldbname')."...\n");
  eval {
    system("$Bin/../update_attributes.pl $options") == 0
      or $support->throw("Error running update_attributes.pl: $!");
    $support->log_stamped("Done.\n\n");
  };
}

# delete any pre existing mappings
if (! $support->param('dry_run')) {
  delete_mappings('ensembl',$dbh->{'ensembl'});
}

# create ensembl-vega (target) database
my $evega_db = $support->param('evegadbname');
my $sth = $dbh->{'vega'}->prepare("SHOW databases");
$sth->execute;
my $found = 0;
if (grep {$_->[0] eq $evega_db} @{$sth->fetchall_arrayref}) {
  $support->log_error("The ensembl-vega db $evega_db already exists. Please drop it manually and start again\n");
}

$support->log("Creating new ensembl-vega db...\n");
$dbh->{'vega'}->do("CREATE DATABASE $evega_db") unless ($support->param('dry_run'));
$support->log_stamped("Done.\n\n");

# load schema into ensembl-vega db
$support->log_stamped("Loading schema...\n");
my $schema_file = $SERVERROOT.'/ensembl/sql/table.sql';
$support->log_error("Cannot open $schema_file.\n") unless (-e $schema_file);
my $cmd = "mysql".
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

#make a note of  meta keys we've just loaded since we don't want to overwrite these with ones from Ensembl later
$sql= "select distinct meta_key from meta";
$sth = $dbh->{'evega'}->prepare($sql) or $support->log_error("Couldn't prepare statement: " . $dbh->errstr);
$sth->execute() or $support->log_error("Couldn't execute statement: " . $sth->errstr);
my @orig_meta_keys = @{$sth->fetchall_arrayref};
my $orig_meta_keys = join("','", map {$_->[0]} @orig_meta_keys);

# transfer chromosome seq_regions from Vega db (with same internal IDs and
# names as in source db)
my $c = 0;
my $vegaassembly = $support->param('assembly');

$support->log_stamped("Transfering Vega chromosome seq_regions...\n");
$sql = qq(
    INSERT INTO $evega_db.seq_region
    SELECT sr.*
    FROM seq_region sr, coord_system cs
    WHERE sr.coord_system_id = cs.coord_system_id
    AND cs.name = 'chromosome'
    AND cs.version = '$vegaassembly'
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c Vega seq_regions.\n\n");
unless ($c > 1) {
  $support->log_warning("Only $c Vega seq_regions on assembly $vegaassembly transferred - is this really correct ?\n");
}

### transfer seq_regions from Ensembl db
$support->log_stamped("Transfering Ensembl seq_regions...\n");

# retrieve adjustment factors for Ensembl seq_region_ids (used when making Vega)
$sql = qq(
    SELECT meta_value
    FROM meta
    WHERE meta_key = 'sri_adjust'
);
my ($sri_adjust) = $dbh->{'vega'}->selectrow_array($sql);

$support->log("Retrieved adjustment factor of $sri_adjust for seq_region_ids...\n",1);
# determine max(coord_system_id) in Vega and use to offset the Ensembl seq_regions so they don't clash
$sth = $dbh->{'evega'}->prepare("SELECT MAX(coord_system_id) FROM seq_region");
$sth->execute;
my ($max_csi) = $sth->fetchrow_array;
my $csi_adjust = 10**(length($max_csi));
$support->log("Using adjustment factor of $csi_adjust for coord_system_ids...\n",1);

#put these in the db so finish_ensembl_vega can use them
$sql = qq(INSERT into meta values ('','','sri_adjust',$sri_adjust),('','','csi_adjust',$csi_adjust));
$dbh->{'evega'}->do($sql) unless ($support->param('dry_run'));


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

# transfer seq_region_synonyms from Ensembl
$support->log_stamped("Transfering Ensembl seq_region_synonyms...\n");
$sql = qq(
    INSERT INTO $evega_db.seq_region_synonym (seq_region_id, synonym, external_db_id)
    SELECT srs.seq_region_id+$sri_adjust, srs.synonym, srs.external_db_id
    FROM seq_region_synonym srs
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c seq_region_synonym entries.\n\n");

#transfer attrib_type table from Vega
$support->log_stamped("Transfering Vega attrib_type...\n");
$sql = qq(
    INSERT INTO $evega_db.attrib_type
    SELECT *
    FROM attrib_type
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c attrib_type entries.\n\n");

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

# transfer assembly_exceptions from Ensembl db
$support->log_stamped("Transfering Ensembl assembly_exception entries...\n");
$sql = qq(
    INSERT INTO $evega_db.assembly_exception
    SELECT '',seq_region_id+$sri_adjust, seq_region_start, seq_region_end,
           exc_type, exc_seq_region_id+$sri_adjust, seq_region_start, seq_region_end, ori
      FROM assembly_exception
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

# transfer ensembl karyotype data
$support->log_stamped("Transfering karyotype info from Ensembl...\n");
$sql = qq(
    INSERT into $evega_db.karyotype
    SELECT karyotype_id, seq_region_id+$sri_adjust, seq_region_start,
           seq_region_end, band, stain from karyotype
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$sql = qq(
    INSERT into $evega_db.meta_coord
    SELECT table_name, coord_system_id+$csi_adjust, max_length
      FROM meta_coord where table_name = 'karyotype'
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done inserting Ensembl karyotype data.\n\n");

# transfer Interpro xrefs and table from Vega db
$support->log_stamped("Transfering Vega Interpro xrefs...\n");
$sql = qq(
    INSERT INTO $evega_db.xref
    SELECT x.*
    FROM xref x, external_db ed
    WHERE x.external_db_id = ed.external_db_id
    AND ed.db_name = 'Interpro'
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c Interpro xrefs.\n\n");
$support->log_stamped("Transfering Vega Interpro table...\n");
$sql = qq(
    INSERT INTO $evega_db.interpro
    SELECT * FROM interpro
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c interpro entries.\n\n");
if ($c eq '0E0') { $support->log_warning("No Vega interpro entries transferred\n"); }

# add appropriate entries to coord_system
$support->log_stamped("Adding coord_system entries...\n");
$sql = qq(
    INSERT INTO $evega_db.coord_system
    SELECT coord_system_id, species_id, name, version, rank+100, attrib
    FROM coord_system cs
    WHERE cs.name = 'chromosome'
    AND cs.version = '$vegaassembly'
);
$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$sql = qq(
    INSERT INTO $evega_db.coord_system
    SELECT coord_system_id+$csi_adjust, species_id, name, version, rank, attrib
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

# populate meta from ensembl, ignoring keys that were loaded from table.sql
$support->log_stamped("Tranfering meta...\n");
$sql = qq(
    INSERT IGNORE INTO $evega_db.meta
    SELECT * FROM meta
     WHERE meta_key not in ('$orig_meta_keys')
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done transfering $c meta entries.\n\n");

# remove genebuild.version from meta table
$sql="delete from meta where meta_key = 'genebuild.version'";
$dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));

# add assembly.mapping to meta table
# get the values for vega_assembly and ensembl_assembly from the db
my $ensembl_assembly;
my $vega_assembly;
$sql= "select meta_value from meta where meta_key= 'assembly.default'";
$sth = $dbh->{'ensembl'}->prepare($sql) or $support->log_error("Couldn't prepare statement: " . $dbh->errstr);
$sth->execute() or $support->log_error("Couldn't execute statement: " . $sth->errstr);
while (my @row = $sth->fetchrow_array()) {
  $ensembl_assembly= $row[0];
}
$sth = $dbh->{'vega'}->prepare($sql) or $support->log_error("Couldn't prepare statement: " . $dbh->errstr);
$sth->execute() or $support->log_error("Couldn't execute statement: " . $sth->errstr);
while (my @row = $sth->fetchrow_array()) {
  $vega_assembly= $row[0];
}
$support->log_stamped("Adding assembly.mapping entry to meta table...\n");
my $mappingstring = 'chromosome:'.$vega_assembly. '#chromosome:'.$ensembl_assembly;
$sql = qq(
    INSERT INTO $evega_db.meta (meta_key, meta_value)
    VALUES ('assembly.mapping', '$mappingstring')
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done inserting $c meta entries.\n\n");


#add assembly mappings from vega
$support->log_stamped("Adding assembly mappings from vega database...\n");
$sql = qq(
    INSERT INTO $evega_db.assembly
    SELECT a.asm_seq_region_id, a.cmp_seq_region_id, a.asm_start, a.asm_end, a.cmp_start, a.cmp_end, a.ori
      FROM assembly a, seq_region sr, coord_system cs
     WHERE a.cmp_seq_region_id = sr.seq_region_id
       AND sr.coord_system_id = cs.coord_system_id
       AND cs.version = \'$ensembl_assembly\'
       AND cs.name = 'chromosome');

$c = $dbh->{'vega'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done inserting $c assembly mapping entries.\n");

#had problems for GRCh38 so now check that the entries added above actually link up with the seq_region table
$sql = qq(SELECT count(*)
            FROM $evega_db.coord_system cs, $evega_db.seq_region sr, $evega_db.assembly a, $evega_db.seq_region sr2, $evega_db.coord_system cs2
           WHERE cs.coord_system_id = sr.coord_system_id
             AND sr.seq_region_id = a.asm_seq_region_id
             AND a.cmp_seq_region_id = sr2.seq_region_id
             AND sr2.coord_system_id = cs2.coord_system_id
             AND cs.name = 'chromosome'
             AND cs2.name = 'chromosome'
             AND cs.version = \'$vega_assembly\'
             AND cs2.version = \'$ensembl_assembly\');
unless ($support->param('dry_run')) {
  my ($check) = $dbh->{'vega'}->selectrow_array($sql);
  if ($check != $c) {
    $support->log_warning("There were $c inserted assembly mapping entries but only $check can be retrieved after linking to the seq_region table.\n");
  }
}

#update external_db and attrib_type on ensembl_vega
if (! $support->param('dry_run') ) {
  # run update_external_dbs.pl
  $params->{'replace'}{'dbname'}  = $support->param('evegadbname');
  $params->{'replace'}{'logfile'} = 'make_ensembl_vega_update_external_dbs.log';
  my $options = $support->create_commandline_options($params);
  $support->log_stamped("\nUpdating external_db table on ".$support->param('evegadbname')."...\n");
  eval {
    system("../xref/update_external_dbs.pl $options") == 0
      or $support->warning("Error running update_external_dbs.pl: $!");
    $support->log_stamped("Done.\n\n");
  };
}

# copy seq_region_mapping and mapping_set
$support->log_stamped("Adding seq_region_mapping and mapping_set...\n");
$sql = qq(
    INSERT INTO $evega_db.seq_region_mapping
      SELECT * FROM seq_region_mapping
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done inserting $c seq_region_mapping entries.\n\n");
$sql = qq(
    INSERT INTO $evega_db.mapping_set
      SELECT * FROM mapping_set
);
$c = $dbh->{'ensembl'}->do($sql) unless ($support->param('dry_run'));
$support->log_stamped("Done inserting $c mapping_set entries.\n\n");

# finish logfile
$support->finish_log;



# delete all unwanted mappings e.g. references to NCBI36 in a GRCh37 db
sub delete_mappings{
  my ($db_type,$dbh) = @_;
  my @db_types=();
  my @row=();
  my $sth = $dbh->prepare("select coord_system_id, name, version from coord_system where name='chromosome'") 
    or $support->log_error("Couldn't prepare statement: " . $dbh->errstr);
  $sth->execute() or $support->log_error("Couldn't execute statement: " . $sth->errstr);
  while (@row = $sth->fetchrow_array()) {
    push @db_types, {coord_system_id => $row[0], name => $row[1], version => $row[2]};
  }
  $sth = $dbh->prepare("select meta_value from meta where meta_key = 'assembly.default'");
  $sth->execute() or $support->log_error("Couldn't execute statement: " . $sth->errstr);
  my ($assembly_version) = $sth->fetchrow_array;
  foreach my $assembly (@db_types) {
    if ($assembly->{'version'} ne $assembly_version) {
      my $version_to_delete = $assembly->{'version'};
      my $id_to_delete = $assembly->{'coord_system_id'};
      if ($support->param('interactive') and $support->user_proceed("Remove $version_to_delete assembly mappings from this copy of the $db_type database?")) {
	$support->log("Removing $version_to_delete assembly mappings from $db_type database\n");
	
	# delete old seq_regions and assemblies that contain them
	my $query= "delete a, sr from seq_region sr left join assembly a on sr.seq_region_id = a.cmp_seq_region_id where sr.coord_system_id = $id_to_delete";
	$dbh->do($query) or $support->log_error("Query failed to delete old seq regions and assembies");
	$support->log("Deleted $version_to_delete assemblies and seq_regions\n");		
		
	# delete the old coord_system from the coord_system table
	$query= "delete from coord_system where coord_system_id = $id_to_delete";
	$dbh->do($query) or $support->log_error("Query failed to delete old coord_system");
	$support->log("Deleted $version_to_delete coord_system\n");

	# delete from the meta table
	$query= "delete from meta where meta_value like '%:$version_to_delete%'";
	$dbh->do($query) or $support->log_error("Query failed to delete old meta entries");
	$support->log("Deleted $version_to_delete meta table entries\n");

	#delete any other coord systems with the same version (eg supercontigs)
	my $sth = $dbh->prepare("select coord_system_id, name, version from coord_system where version = \'$version_to_delete\'");
	$sth->execute;
	while (my ($id_to_delete, $name, $version) = $sth->fetchrow_array()) {
	  $support->log("Removing additional $version ($name) assembly mappings from $db_type database\n");
	  $query = "delete from seq_region where coord_system_id = $id_to_delete";
	  $dbh->do($query) or $support->log_error("Query failed to delete old seq regions");
	  $support->log("Deleted $version $name seq_regions\n");				
	  $query = "delete from coord_system where coord_system_id = $id_to_delete";
	  $dbh->do($query) or $support->log_error("Query failed to delete old coord_system");
	  $support->log("Deleted $version $name coord_system\n");
	}
	$query = "delete a from assembly a left join seq_region sr on a.cmp_seq_region_id = sr.seq_region_id where sr.seq_region_id is null";
	$dbh->do($query) or $support->log_error("Query failed to delete old cmp_seqregion ids from assembly");
	$query = "delete a from assembly a left join seq_region sr on a.asm_seq_region_id = sr.seq_region_id where sr.seq_region_id is null";
	$dbh->do($query) or $support->log_error("Query failed to delete old asm_seqregion ids from assembly");
	$support->log("Removed any orphan seq_regions from assembly table of $db_type database\n");
      }
    }
  }
  return;
}
