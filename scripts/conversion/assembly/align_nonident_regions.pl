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

align_nonident_regions.pl - create whole genome alignment between two closely
related assemblies for non-identical regions

=head1 SYNOPSIS

align_nonident_regions.pl [options]

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
    --evegahost=HOST                    use ensembl-vega (target) database host
                                        HOST
    --evegaport=PORT                    use ensembl-vega (target) database port
                                        PORT
    --evegauser=USER                    use ensembl-vega (target) database
                                        username USER
    --evegapass=PASS                    use ensembl-vega (target) database
                                        passwort PASS
    --chromosomes, --chr=LIST           only process LIST chromosomes
    --mismatch_allowed                  allow for mismatches in alignment (default is NO)
    --bindir=DIR                        look for program binaries in DIR
    --tmpfir=DIR                        use DIR for temporary files (useful for
                                        re-runs after failure)

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

It creates a whole genome alignment between two closely related assemblies for
non-identical regions. These regions are identified by another script
(align_by_clone_identity.pl) and stored in a temporary database table
(tmp_align).

Alignments are calculated by this algorithm:

    1. fetch region from tmp_align
    2. write soft-masked sequences to temporary files
    3. align using blastz
    4. filter best hits (for query sequences, i.e. Ensembl regions) using
       axtBest
    5. parse blastz output to create blocks of exact (or mismatched) matches
    6. remove overlapping target (Vega) alignments
    7. write alignments to assembly table

=head1 RELATED SCRIPTS

The whole Ensembl-vega database production process is done by these scripts:

    ensembl-otter/scripts/conversion/assembly/make_ensembl_vega_db.pl
    ensembl-otter/scripts/conversion/assembly/align_by_clone_identity.pl
    ensembl-otter/scripts/conversion/assembly/align_nonident_regions.pl
    ensembl-otter/scripts/conversion/assembly/map_annotation.pl
    ensembl-otter/scripts/conversion/assembly/finish_ensembl_vega_db.pl

See documention in the respective script for more information.


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
    unshift(@INC, "./modules");
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use BlastzAligner;

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
    'bindir=s',
    'tmpdir=s',
    'chromosomes|chr=s@',
    'mismatch_allowed=s',
);
$support->allowed_params(
    $support->get_common_params,
    'evegahost',
    'evegaport',
    'evegauser',
    'evegapass',
    'evegadbname',
    'bindir',
    'tmpdir',
    'chromosomes',
    'mismatch_allowed',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

my $mismatch_allowed = $support->param('mismatch_allowed') ? $support->param('mismatch_allowed') : 0 ;

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $V_dba = $support->get_database('core');
my $V_dbh = $V_dba->dbc->db_handle;
my $V_sa = $V_dba->get_SliceAdaptor;
my $E_dba = $support->get_database('evega', 'evega');
my $E_dbh = $E_dba->dbc->db_handle;
my $E_sa = $E_dba->get_SliceAdaptor;

# create BlastzAligner object
my $aligner = BlastzAligner->new(-SUPPORT => $support);

# create tmpdir to store input and output
$aligner->create_tempdir($support->param('tmpdir'));

# loop over non-aligned regions in tmp_align table
$support->log_stamped("Looping over non-aligned blocks...\n");

my $sql = qq(SELECT * FROM tmp_align);
if ($support->param('chromosomes')) {
  my $chr_string = join(", ", $support->param('chromosomes'));
  $sql .= " WHERE v_seq_region_name IN ($chr_string)";
}
my $sth = $E_dbh->prepare($sql);
$sth->execute;

while (my $row = $sth->fetchrow_hashref) {
    my $id = $row->{'tmp_align_id'};
    $aligner->id($id);
    $aligner->seq_region_name($row->{'v_seq_region_name'});

    $support->log_stamped("Block with tmp_align_id = $id\n", 1);
    my $E_slice = $E_sa->fetch_by_region(
        'chromosome',
        $row->{'e_seq_region_name'},
        $row->{'e_start'},
        $row->{'e_end'},
        1,
        $support->param('ensemblassembly'),
    );
    my $V_slice = $V_sa->fetch_by_region(
        'chromosome',
        $row->{'v_seq_region_name'},
        $row->{'v_start'},
        $row->{'v_end'},
        1,
        $support->param('assembly'),
    );

    # write sequences to file, and convert sequence files from fasta to nib
    # format (needed for lavToAxt)
    my $E_basename = "e_seq.$id";
    my $V_basename = "v_seq.$id";
    $support->log("Writing sequences to fasta and nib files...\n", 2);
    $aligner->write_sequence(
        $E_slice,
        $support->param('ensemblassembly'),
        $E_basename
    );
    $aligner->write_sequence(
        $V_slice,
        $support->param('assembly'),
        $V_basename
    );
    $support->log("Done.\n", 2);

    # align using blastz
    $support->log("Running blastz...\n", 2);
    $aligner->run_blastz($E_basename, $V_basename);
    $support->log("Done.\n", 2);

    # convert blastz output from lav to axt format
    $support->log("Converting blastz output from lav to axt format...\n", 2);
    $aligner->lav_to_axt;
    $support->log("Done.\n", 2);

    # find best alignment with axtBest
    $support->log("Finding best alignment with axtBest...\n", 2);
    $aligner->find_best_alignment;
    $support->log("Done.\n", 2);

    # parse blastz output, and convert relative alignment coordinates to
    # chromosomal coords
    $support->log("Parsing blastz output...\n", 2);
    $aligner->parse_blastz_output($mismatch_allowed);
    $aligner->adjust_coords(
        $row->{'e_start'},
        $row->{'e_end'},
        { $id => [ $row->{'v_start'}, $row->{'v_end'} ] }
    );
    $support->log("Done.\n", 2);

    # cleanup temp files
    $support->log("Cleaning up temp files...\n", 2);
    $aligner->cleanup_tmpfiles(
      "$E_basename.fa",
      "$E_basename.nib",
      "$V_basename.fa",
      "$V_basename.nib",
    );
    $support->log("Done.\n", 2);

    # log alignment stats
    $aligner->log_block_stats(2);

    $support->log_stamped("Done with block $id.\n", 1);
}
$support->log_stamped("Done.\n");

# filter overlapping Vega alignment regions if we're not allowing mismatches (otherwise need to remove them using fix_overlaps.pl)
unless ($mismatch_allowed) {
  $support->log_stamped("Filtering overlapping Vega alignment regions...\n");
  $aligner->filter_overlaps;
}
$support->log_stamped("Done.\n");

# write alignments to assembly table
unless ($support->param('dry_run')) {
    $aligner->write_assembly($V_dba, $E_dbh, $E_sa);
}

# cleanup
$support->log_stamped("\nRemoving tmpdir...\n");
$aligner->remove_tempdir;
$support->log_stamped("Done.\n");

# drop tmp_align
#unless ($support->param('dry_run')) {
#    if ($support->user_proceed("Would you like to drop the tmp_align table?")) {
#        $support->log_stamped("Dropping tmp_align table...\n");
#        $E_dbh->do(qq(DROP TABLE tmp_align));
#        $support->log_stamped("Done.\n");
#    }
#}

# overall stats
$aligner->log_overall_stats;

# finish logfile
$support->finish_log;


