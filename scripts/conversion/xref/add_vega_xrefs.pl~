#!/usr/local/bin/perl

=head1 NAME

add_vega_xrefs.pl - add xrefs to display gene, transcript and translation names

=head1 SYNOPSIS

add_vega_xrefs.pl [options]

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
    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gene_stable_id, --gsi=LIST|FILE   only process LIST gene_stable_ids
                                        (or read list from FILE)
    --gene_type=TYPE                    only process genes of type TYPE
    --start_gid=NUM                     start at gene with gene_id NUM
    --prune                             delete all xrefs (except Interpro) and
                                        gene/transcript.display_xref_ids before
                                        running the script

=head1 DESCRIPTION

This script retrieves annotated gene/transcript names and adds them as xrefs
to genes/transcripts/translations, respectively, setting them as display_xrefs.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Patrick Meidl <pm2@sanger.ac.uk>
Original code by Tim Hubbard <th@sanger.ac.uk>

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
    'chromosomes|chr=s@',
    'gene_stable_id|gsi=s@',
    'gene_type=s',
    'start_gid=s',
    'prune',
);
$support->allowed_params(
    $support->get_common_params,
    'chromosomes',
    'gene_stable_id',
    'gene_type',
    'start_gid',
    'prune',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->list_or_file('gene_stable_id');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors (caching features on one slice only)
my $dba = $support->get_database('otter');
my $sa = $dba->get_SliceAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $ea = $dba->get_DBEntryAdaptor();
# statement handles for display_xref_id updates
my $sth_gene = $dba->dbc->prepare("update gene set display_xref_id=? where gene_id=?");
my $sth_trans = $dba->dbc->prepare("update transcript set display_xref_id=? where transcript_id=?");

# delete all xrefs if --prune option is used
if ($support->param('prune') and $support->user_proceed('Would you really like to delete all xrefs (except Interpro) before running this script?')) {

    my $num;
    
    # xrefs
    $support->log("Deleting all xrefs (except Interpro)...\n");
    $num = $dba->dbc->do(qq(
        DELETE x
        FROM xref x, external_db ed
        WHERE x.external_db_id = ed.external_db_id
        AND ed.db_name <> 'Interpro'
    ));
    $support->log("Done deleting $num entries.\n");

    # object_xrefs
    $support->log("Deleting all object_xrefs...\n");
    $num = $dba->dbc->do(qq(DELETE FROM object_xref));
    $support->log("Done deleting $num entries.\n");

    # gene.display_xref_id
    $support->log("Resetting gene.display_xref_id...\n");
    $num = $dba->dbc->do(qq(UPDATE gene set display_xref_id = 0));
    $support->log("Done resetting $num genes.\n");
    
    # transcript.display_xref_id
    $support->log("Resetting transcript.display_xref_id...\n");
    $num = $dba->dbc->do(qq(UPDATE transcript set display_xref_id = 0));
    $support->log("Done resetting $num transcripts.\n");
}

my $found = 0;
my @gene_stable_ids = $support->param('gene_stable_id');
my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);

# loop over chromosomes
$support->log("Looping over chromosomes: @chr_sorted\n\n");
foreach my $chr (@chr_sorted) {
    $support->log("> Chromosome $chr (".$chr_length->{$chr}
               ."bp). ".$support->date_and_mem."\n\n");
    
    # fetch genes from db
    $support->log("Fetching genes...\n");
    my $slice = $sa->fetch_by_region('toplevel', $chr);
    my $genes = $ga->fetch_by_Slice($slice);
    $support->log("Done fetching ".scalar @$genes." genes. " .
                   $support->date_and_mem."\n\n");

    # loop over genes
    my ($gnum, $tnum, $tlnum);
    foreach my $gene (@$genes) {
        my $gsi = $gene->stable_id;
        my $gid = $gene->dbID;

        # filter to user-specified gene_stable_ids
        if (scalar(@gene_stable_ids)){
            next unless $gene_stable_ids{$gsi};
        }

        my $gene_name;
        if ($gene->gene_info->name && $gene->gene_info->name->name) {
            $gene_name = $gene->gene_info->name->name;
        } else {
            $support->log_warning("Gene $gid ($gsi) has no gene_name.name.\n");
            $gene_name = $gsi;
        }

        $support->log("Gene $gene_name ($gid, $gsi)...\n");

        # filter to user-specified gene_type
        my $gene_type = $support->param('gene_type');
        if ($gene_type and ($gene_type ne $gene->type)){
            $support->log("Skipping gene - not of type $gene_type.\n", 1);
            next;
        }

        # allow a restart of script at specified gene_stable_id
        if($support->param('start_gid') && !$found){
            if($gid == $support->param('start_gid')){
                $found = 1;
                $support->log("Found $gid - starting at next gene.\n", 1);
            } else {
                $support->log("Skipping gene - waiting for start gene_id.\n", 1);
            }
            next;
        }

        # add the gene name as an xref to db
        $gnum++;
        my $dbentry = Bio::EnsEMBL::DBEntry->new(
                -primary_id => $gene->stable_id,
                -display_id => $gene_name, 
                -version    => 1,
                -release    => 1,
                -dbname     => "Vega_gene",
        );
        $dbentry->status('KNOWN');
        $gene->add_DBEntry($dbentry);
        unless ($support->param('dry_run')) {
            my $dbID = $ea->store($dbentry, $gid, 'Gene');
            $sth_gene->execute($dbID, $gid);
            $support->log("Stored xref $dbID for gene $gid.\n", 1);
        }

        # loop over transcripts
        foreach my $trans (@{$gene->get_all_Transcripts}){
            my $tid = $trans->dbID;
            my $tsi = $trans->stable_id;
            my $trans_name;
            if ($trans->transcript_info->name) {
                $trans_name = $trans->transcript_info->name;
            } else {
                $trans_name = $tsi;
            }
            
            $support->log("Transcript $trans_name ($tid, $tsi)...\n", 1);

            # add transcript name as an xref to db
            $tnum++;
            my $dbentry = Bio::EnsEMBL::DBEntry->new(
                    -primary_id=>$trans->stable_id,
                    -display_id=>$trans_name, 
                    -version=>1,
                    -release=>1,
                    -dbname=>"Vega_transcript",
                    );
            $dbentry->status('KNOWN');
            unless ($support->param('dry_run')) {
                my $dbID = $ea->store($dbentry, $tid, 'Transcript');
                $sth_trans->execute($dbID, $tid);
                $support->log("Stored xref $dbID for transcript $tid.\n", 2);
            }

            # translations
            my $translation = $trans->translation;
            if ($translation) {
                # add translation name as xref to db
                $tlnum++;
                my $tlid = $translation->stable_id;
                my $dbentry = Bio::EnsEMBL::DBEntry->new(
                        -primary_id=>$tlid,
                        -display_id=>$tlid, 
                        -version=>1,
                        -release=>1,
                        -dbname=>"Vega_translation",
                        );
                $dbentry->status('KNOWN');
                unless ($support->param('dry_run')) {
                    $ea->store($dbentry, $trans->translation->dbID, 'Translation');
                    $support->log("Stored xref ".$dbentry->dbID." for translation $tlid.\n", 2);
                }
            }
        }
    }

    $support->log("\nAdded xrefs for $gnum (of ".scalar @$genes.") genes, $tnum transcripts, $tlnum translations.\n");
    $support->log("Done with chromosome $chr. ".$support->date_and_mem."\n\n");
}

# finish log
$support->finish_log;

