#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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
    --evegahost=HOST                    use ensembl-vega (target) database host HOST
    --evegaport=PORT                    use ensembl-vega (target) database port PORT
    --evegauser=USER                    use ensembl-vega (target) database username USER
    --evegapass=PASS                    use ensembl-vega (target) database password PASS

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

This script does some final adjustments to an Ensembl-vega database. This
includes:

    - deleting data not needed any more (eg dna, repeats)
    - updating seq_region_ids to match those in the core Ensembl db
    - transfer selenocysteines
    - checking and setting the analysis_id and source for all genes and transcripts
    - delete orphan entries from object_xref

=head1 RELATED SCRIPTS

The whole Ensembl-vega database production process is done by these scripts:

    ensembl-otter/scripts/conversion/assembly/make_ensembl_vega_db.pl
    ensembl-otter/scripts/conversion/assembly/map_annotation.pl
    ensembl-otter/scripts/conversion/assembly/finish_ensembl_vega_db.pl

See documention in the respective script for more information.


=head1 AUTHOR

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
my ($dba, $dbh, $sql, $sth, $c);
$dba->{'vega'}  = $support->get_database('core');
$dbh->{'vega'}  = $dba->{'vega'}->dbc->db_handle;
$dba->{'evega'} = $support->get_database('evega', 'evega');
$dbh->{'evega'} = $dba->{'evega'}->dbc->db_handle;
my $ensembl_db  = $support->param('ensembldbname');
my $vega_db     = $support->param('dbname');

my $ensemblassembly = $support->param('ensemblassembly');
my $vegaassembly    = $support->param('assembly');

# retrieve adjustment factors for Ensembl seq_region_ids and coord_system_ids
$sql = qq(
    SELECT meta_key, meta_value
    FROM meta
    WHERE meta_key in ('sri_adjust','csi_adjust')
);
$sth = $dbh->{'evega'}->prepare($sql);
$sth->execute;
my %meta_values;
while (my ($meta_key, $meta_value) = $sth->fetchrow_array) {
  $meta_values{$meta_key} = $meta_value;
}
my $E_sri_adjust = $meta_values{'sri_adjust'};
my $E_csi_adjust = $meta_values{'csi_adjust'};

unless ($E_sri_adjust && $E_csi_adjust) {
  $support->log_error("Can't retrieve adjust values from meta table so you'll have problems - look at the make_ensembl_vega_db log to see what they should be\n");
}
$support->log("Will use a value of $E_sri_adjust to adjust Ensembl seq_regions, and $E_csi_adjust to adjust Ensembl coord_systems\n");

# store Vega chromosome seq_regions and Ensembl-Vega assembly in temporary tables
$support->log_stamped("Storing Vega chromosome seq_regions and Ensembl-Vega assembly in temporary tables...\n");
$sql = qq(
    CREATE TABLE tmp_seq_region
    SELECT sr.*
    FROM   seq_region sr,
           coord_system cs
    WHERE sr.coord_system_id = cs.coord_system_id
    AND cs.name = 'chromosome'
    AND cs.version = '$vegaassembly'
);
my $c1 = $dbh->{'evega'}->do($sql);
$sql = qq(
    CREATE TABLE tmp_assembly
    SELECT a.*
    FROM   assembly a,
           seq_region sr1,
           seq_region sr2,
           coord_system cs1,
           coord_system cs2
    WHERE a.asm_seq_region_id = sr1.seq_region_id
    AND a.cmp_seq_region_id = sr2.seq_region_id
    AND sr1.coord_system_id = cs1.coord_system_id
    AND sr2.coord_system_id = cs2.coord_system_id
    AND cs1.name = 'chromosome'
    AND cs2.name = 'chromosome'
    AND cs1.version = '$vegaassembly'
    AND cs2.version = '$ensemblassembly'
);

my $c2 = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done storing $c1 seq_region and $c2 assembly entries.\n\n");

## adjust all coord_system_ids
$support->log_stamped("Adjusting coord_system_ids...\n");
$sth = $dbh->{'evega'}->prepare("SELECT MAX(coord_system_id) FROM coord_system");
$sth->execute;
my ($tmp_max_csi) = $sth->fetchrow_array;
my $V_csi_adjust = 10**(length($tmp_max_csi));
# delete all but the Vega chromosome coord system
$sql = qq(
    DELETE FROM coord_system
    WHERE NOT (name = 'chromosome' AND version = '$vegaassembly')
);
$c = $dbh->{'evega'}->do($sql);
# adjust Vega coord_system_ids
$sql = qq(
    UPDATE coord_system
    SET coord_system_id = coord_system_id+$V_csi_adjust
);
$c = $dbh->{'evega'}->do($sql);
$sql = qq(
    UPDATE tmp_seq_region
    SET coord_system_id = coord_system_id+$V_csi_adjust
);
$c = $dbh->{'evega'}->do($sql);
# add Ensembl coord_systems
$sql = qq(
    INSERT INTO coord_system
    SELECT *
    FROM $ensembl_db.coord_system
);
$c = $dbh->{'evega'}->do($sql);
# meta_coord
$sql = qq(
    DELETE FROM meta_coord
    WHERE coord_system_id < $E_csi_adjust
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c meta_coord entries.\n");
$sql = qq(
    UPDATE meta_coord
    SET coord_system_id = coord_system_id-$E_csi_adjust
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done.\n\n");

# adjust seq_region_ids in tmp_seq_region and tmp_assembly
$support->log_stamped("Adjusting Vega seq_region_ids in tmp_assembly and tmp_seq_region...\n");
$sth = $dbh->{'evega'}->prepare("SELECT MAX(seq_region_id)+1 FROM $ensembl_db.seq_region");
$sth->execute;
my ($V_sri_adjust) = $sth->fetchrow_array;

$support->log("Adjustment factors: $V_sri_adjust for Vega, $E_sri_adjust for Ensembl seq_region_ids.\n", 1);
$sql = qq(
    UPDATE tmp_seq_region
    SET seq_region_id = seq_region_id+$V_sri_adjust
);
$c = $dbh->{'evega'}->do($sql);
$sql = qq(
    UPDATE  tmp_assembly a
    SET     a.asm_seq_region_id = a.asm_seq_region_id+$V_sri_adjust,
            a.cmp_seq_region_id = a.cmp_seq_region_id-$E_sri_adjust
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done.\n\n");

# delete from assembly, seq_region, dna repeat_consensus, repeat_feature
$support->log_stamped("Deleting assembly...\n");
$sql = qq(DELETE FROM assembly);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c assembly entries.\n\n");

$support->log_stamped("Deleting assembly_exception...\n");
$sql = qq(DELETE FROM assembly_exception);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c assembly_exception entries.\n\n");

$support->log_stamped("Deleting seq_region...\n");
$sql = qq(DELETE FROM seq_region);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c seq_region entries.\n\n");

$support->log_stamped("Deleting seq_region_attrib...\n");
$sql = qq(DELETE FROM seq_region_attrib);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c seq_region_attrib entries.\n\n");

$support->log_stamped("Deleting seq_region_synonym...\n");
$sql = qq(DELETE FROM seq_region_synonym);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c seq_region_synonym entries.\n\n");

$support->log_stamped("Deleting dna...\n");
$sql = qq(DELETE FROM dna);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c dna entries.\n\n");

$support->log_stamped("Deleting repeat_consensus...\n");
$sql = qq(DELETE FROM repeat_consensus);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c repeat_consensus entries.\n\n");

$support->log_stamped("Deleting repeat_feature...\n");
$sql = qq(DELETE FROM repeat_feature);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done deleting $c repeat_feature entries.\n\n");

# transfer assembly, assembly_exception, seq_region, seq_region_attribs from Ensembl db
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

$support->log_stamped("Transfering Ensembl seq_region_synonyms...\n");
$sql = qq(
    INSERT INTO seq_region_synonym
    SELECT *
    FROM $ensembl_db.seq_region_synonym
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done transfering $c seq_region_synonym entries.\n\n");

# transfer Ensembl-Vega assembly information from tmp_seq_region and tmp_assembly back into main tables
$support->log_stamped("Adding Vega seq_regions from tmp tables...\n");
$sql = qq(
    INSERT INTO seq_region
    SELECT * FROM tmp_seq_region
);
my $c3 = $dbh->{'evega'}->do($sql);
$support->log_stamped("Adding Ensembl-Vega assembly mapping info from tmp tables...\n");
$sql = qq(
    INSERT INTO assembly
    SELECT * from tmp_assembly
);
my $c4 = $dbh->{'evega'}->do($sql);
$support->log_stamped("Done adding $c3 seq_region and $c4 assembly entries.\n\n");

# now adjust all seq_region_ids
$support->log_stamped("Updating seq_region_ids on all tables:\n");
# exon
$support->log_stamped("exon...\n", 1);
$sql = qq(UPDATE exon SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);
# gene
$support->log_stamped("gene...\n", 1);
$sql = qq(UPDATE gene SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);
# transcript
$support->log_stamped("transcript...\n", 1);
$sql = qq(UPDATE transcript SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);
# dna_align_feature
$support->log_stamped("dna_align_feature...\n", 1);
$sql = qq(UPDATE dna_align_feature SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);
# protein_align_feature
$support->log_stamped("protein_align_feature...\n", 1);
$sql = qq(UPDATE protein_align_feature SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);
# misc_feature
$support->log_stamped("misc_feature...\n", 1);
$sql = qq(UPDATE misc_feature SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);
# misc_feature
$support->log_stamped("karyotype...\n", 1);
$sql = qq(UPDATE karyotype SET seq_region_id = seq_region_id-$E_sri_adjust);
$c = $dbh->{'evega'}->do($sql);

$support->log_stamped("Done.\n\n");

#fixing gene start/end (since we have not transferred all transcripts some may have changed)
$support->log_stamped("Updating gene starts and ends...\n");
$sql = qq(CREATE TEMPORARY TABLE gene_coords
          SELECT g.gene_id, min(t.seq_region_start) as seq_region_start, max(t.seq_region_end) as seq_region_end
            FROM gene g, transcript t
           WHERE g.gene_id = t.gene_id
           GROUP by g.gene_id);
$dbh->{'evega'}->do($sql);
$sql = qq(UPDATE gene g, gene_coords gc
             SET g.seq_region_start = gc.seq_region_start, g.seq_region_end = gc.seq_region_end
           WHERE g.gene_id = gc.gene_id);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Updated $c gene starts and ends...\n\n");

# selenocysteines / peptide statistics
$support->log_stamped("Transfering Vega translation_attribs (selenocysteines & peptide statistics)...\n");
$sql = qq(
    INSERT INTO translation_attrib
    SELECT t2.translation_id, at2.attrib_type_id, ta.value
    FROM
        $vega_db.translation_attrib ta,
        $vega_db.translation t,
        $vega_db.attrib_type at,
        translation t2,
        attrib_type at2
    WHERE ta.translation_id = t.translation_id
    AND t.stable_id = t2.stable_id
    AND ta.attrib_type_id = at.attrib_type_id
    AND at.code = at2.code
);
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Transferred $c translation_attrib entries.\n\n");

#delete redundant xrefs - these are just to the internal IDs of the vega translations and have to be ignored by the webcode
$support->log_stamped("Deleting redundant Vega translation xrefs...\n");
$sql = qq(DELETE x
            FROM xref x, external_db edb
           WHERE x.external_db_id = edb.external_db_id
             AND edb.db_name = 'Vega_translation'
             AND display_label NOT REGEXP '^OTT'
             AND x.info_text IS NULL);	
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Deleted $c orphan object_xref entries.\n\n");


#delete any orphan object_xref entries
$support->log_stamped("Deleting orphan object_xref entries...\n");
$sql = qq(DELETE ox
            FROM object_xref ox
            LEFT JOIN xref x ON ox.xref_id = x.xref_id
           WHERE x.xref_id IS NULL);	
$c = $dbh->{'evega'}->do($sql);
$support->log_stamped("Deleted $c orphan object_xref entries.\n\n");

#drop the transient tables tmp_assembly and tmp_seq_region
$sql = qq(DROP TABLE tmp_assembly);
$c = $dbh->{'evega'}->do($sql);
$sql = qq(DROP TABLE tmp_seq_region);
$c = $dbh->{'evega'}->do($sql);

##tidy up meta table entries

#remove unwanted ensembl ones
$support->log_stamped("Deleting and updating meta table entries.\n\n");
$sql = qq(DELETE from meta
           WHERE meta_key in ('assembly.num_toplevel_seqs', 'genebuild.vega_merge_db','genebuild.version', 'removed_evidence_flag.ensembl_dbversion', 'removed_evidence_flag.uniprot_dbversion','sri_adjust','csi_adjust','marker.priority','liftover.mapping','assembly.web_accession_type','assembly.web_accession_source','xref.timestamp','repeat.analysis','assembly.date','pipeline.lock','gencode.version','assembly.overlapping_regions','assembly.coverage_depth','assembly.ucsc_alias' ));
$c += $dbh->{'evega'}->do($sql);
$sql = qq(DELETE from meta
           WHERE meta_key in ('genebuild.id','genebuild.method','genebuild.id','genebuild.start_date','genebuild.initial_release_date','genebuild.last_geneset_update','genebuild.havana_datafreeze_date'));
$c += $dbh->{'evega'}->do($sql);
$support->log_stamped("Deleted $c meta table entries.\n\n");

#add genebuild info
$support->log_stamped("Updating genebuild meta entries...\n");
foreach my $meta ('genebuild.level','transcriptbuild.level','exonbuild.level') {
  $sql = qq(
    INSERT IGNORE INTO meta (meta_key,meta_value)
    SELECT meta_key,meta_value FROM $vega_db.meta WHERE meta_key = '$meta');
  $c = $dbh->{'evega'}->do($sql);
}

$sql = qq(
    INSERT IGNORE INTO meta (meta_key,meta_value)
    SELECT meta_key,meta_value FROM $vega_db.meta WHERE meta_key = 'genebuild.start_date');
$c = $dbh->{'evega'}->do($sql);

$sql = qq(
    INSERT IGNORE INTO meta (meta_key,meta_value)
    SELECT meta_key,meta_value FROM $vega_db.meta WHERE meta_key = 'genebuild.havana_datafreeze_date');
$c = $dbh->{'evega'}->do($sql);

$sql = qq(
    INSERT IGNORE INTO meta (meta_key,meta_value)
    SELECT meta_key,meta_value FROM $vega_db.meta WHERE meta_key = 'genebuild.last_geneset_update');
$c = $dbh->{'evega'}->do($sql);
unless ($c) {
  $support->log_warning("Did not insert correct genebuild.last_geneset_update meta key, this will cause HC noise\n");
}

$support->log_stamped("Updating assembly.default entries...\n");
$sth = $dbh->{'evega'}->prepare(qq(SELECT meta_value FROM meta where meta_key = 'assembly.default'));
$sth->execute;
if (my ($assembly_default) = $sth->fetchrow_array) {
  if ($assembly_default ne $ensemblassembly) {
    $support->log_warning("Please check why meta.assembly.default does not equal parameter for ensembl assembly\n");
  }
}
else {
  $c = $dbh->{'evega'}->do(qq(INSERT into meta values ('',1,'assembly.default','$ensemblassembly')));
  $support->log("Inserted $c values for meta.assembly.default\n");
}

#make sure meta table build level matches that in vega and is restricted to tables that have features
$support->log_stamped("Setting meta buildlevel entries...\n");
$dbh->{'evega'}->do(qq(DELETE FROM meta WHERE meta_key LIKE '%build.level'));
$sth =  $dbh->{'vega'}->prepare(qq(SELECT species_id, meta_key, meta_value from meta where meta_key like '%build.level'));
$sth->execute;
foreach my $vme (@{$sth->fetchall_arrayref}) {
  my $table = $vme->[1];
  $table =~ s/build.level//;
  my $c = $dbh->{'evega'}->selectrow_array(qq(SELECT count(*) from $table));
  if ($c) {
    $sql = qq(INSERT INTO meta values ('',$vme->[0],'$vme->[1]','$vme->[2]'));
    if (! $support->param('dry_run')) {
      $dbh->{'evega'}->do($sql);
    }
  }
}

#remove duplicate meta entries
$support->log_stamped("Removing duplicate meta entries...\n");
$c = $dbh->{'evega'}->do(qq(CREATE table nondup_meta like meta));
$c = $dbh->{'evega'}->do(qq(INSERT into nondup_meta (select '',species_id, meta_key, meta_value from meta group by species_id, meta_key, meta_value)));
$c = $dbh->{'evega'}->do(qq(DELETE from meta));
$c = $dbh->{'evega'}->do(qq(INSERT into meta (select * from nondup_meta)));
$c = $dbh->{'evega'}->do(qq(DROP table nondup_meta));

#remove duplicate attribs
$support->log_stamped("Removing any duplicates from attrib tables.\n\n");
foreach my $t (qw(gene transcript translation seq_region)) {
  $support->remove_duplicate_attribs($dbh->{'evega'},$t);
}

#remove orphan codon_usage seq_region_attribs since they keep on appearing (come from core dbs) only to be deleted
$support->log_stamped("Removing orphan codon_usage seq_region_attribs.\n");
$c = $dbh->{'evega'}->do(qq(DELETE sra FROM attrib_type at, seq_region_attrib sra
                                   LEFT JOIN seq_region sr ON sra.seq_region_id = sr.seq_region_id
                             WHERE sra.attrib_type_id = at.attrib_type_id
                               AND at.code = 'codon_table'
                               AND sr.seq_region_id IS NULL));
$support->log("Removed $c seq_region_attib entries\n\n");

#tidy up xrefs with incorrect version (HC noise)
$support->log_stamped("Setting correct default version for xrefs.\n");
$c = $dbh->{'evega'}->do(qq(UPDATE xref SET version = 0 WHERE version = ''));
$support->log("Updated versions of $c xrefs\n\n");
#tidy up xrefs with info_type (HC noise)
$support->log_stamped("Setting correct default info_type for xrefs.\n");
$c = $dbh->{'evega'}->do(qq(UPDATE xref SET info_type = 'NONE' WHERE info_type = ''));
$support->log("Updated info_type of $c xrefs\n");

# finish logfile
$support->finish_log;
