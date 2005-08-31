#!/usr/local/bin/perl

=head1 NAME

transfer_identical_chromosomes.pl - transfer annotation from Vega to Ensembl
assembly on identical chromosomes

=head1 SYNOPSIS

transfer_identical_chromosomes.pl [options]

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

=head1 DESCRIPTION


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
);
$support->allowed_params(
    $support->get_common_params,
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
my ($V_dba, $V_dbh, $E_dba, $E_dbh);
$V_dba = $support->get_database('core');
$V_dbh = $V_dba->dbc->db_handle;
my $V_sa = $V_dba->get_SliceAdaptor;
my $V_pfa = $V_dba->get_ProteinFeatureAdaptor;
$E_dba = $support->get_database('evega', 'evega');
$E_dbh = $E_dba->dbc->db_handle;
my $E_sa = $E_dba->get_SliceAdaptor;
my $E_ga = $E_dba->get_GeneAdaptor;
my $E_pfa = $E_dba->get_ProteinFeatureAdaptor;

# get Vega and Ensembl chromosomes
my $V_chrlength = $support->get_chrlength($E_dba, $support->param('assembly'));
my $E_chrlength = $support->get_chrlength($E_dba, $support->param('ensemblassembly'));

# loop over chromosomes
$support->log_stamped("Looping over chromosomes...\n");
foreach my $chr ($support->sort_chromosomes($V_chrlength)) {
    $support->log_stamped("Chromosome $chr...\n", 1);

    # skip non-ensembl chromosomes (e.g. MHC haplotypes)
    unless ($E_chrlength->{$chr}) {
        $support->log("Chromosome not in Ensembl. Skipping.\n", 1);
        next;
    }

    # fetch chromosome slices
    my $V_slice = $V_sa->fetch_by_region('chromosome', $chr, undef, undef, undef, $support->param('assembly'));
    my $E_slice = $E_sa->fetch_by_region('chromosome', $chr, undef, undef, undef, $support->param('ensemblassembly'));

    # check chromosome identity
    my $identical;
    foreach my $attrib (@{ $E_slice->get_all_Attributes || [] }) {
        $identical = 1 if ($attrib->code eq 'ensembl_ident');
    }

    unless ($identical) {
        # skip non-identical chromosome
        $support->log("Chromosome is not identical. Skipping.\n", 1);
        next;
    }

    # loop over genes
    foreach my $gene (@{ $V_slice->get_all_Genes }) {
        $support->log_verbose("Transferring gene ".$gene->stable_id."\n", 2);
        my %V_pfhash;
        $gene->adaptor($E_ga);
        $gene->slice($E_slice);
        foreach my $transcript (@{ $gene->get_all_Transcripts }) {
            $transcript->slice($E_slice);

            # These lines force loads from the database to stop attempted lazy
            # loading during the write (which fail because they are to the
            # wrong db)
            if (defined($transcript->translation)) {
                $V_pfhash{$transcript->stable_id} = $V_pfa->fetch_by_translation_id($transcript->translation->dbID);
            }

            my @exons= @{ $transcript->get_all_Exons };
            my $get = $transcript->translation;
            $transcript->_translation_id(undef);

            foreach my $exon (@exons) {
                $exon->stable_id;
                $exon->slice($E_slice);
                $exon->get_all_supporting_features; 
            }
        }

        # store the gene on new assembly
        # this doesn't work, since $gene->is_stored is true -> hack it?
        $E_ga->store($gene) unless ($support->param('dry_run'));

        # store supporting evidence
        foreach my $transcript (@{$gene->get_all_Transcripts}) {
            if (defined($V_pfhash{$transcript->stable_id})) {
                foreach my $pf (@{ $V_pfhash{$transcript->stable_id} }) {
                    $pf->seqname($transcript->translation->dbID);
                    if (!$pf->score) { $pf->score(0) };
                    if (!$pf->percent_id) { $pf->percent_id(0) };
                    if (!$pf->p_value) { $pf->p_value(0) };
                    $pf->dbID(undef);
                    $E_pfa->store($pf) unless ($support->param('dry_run'));
                }
            }
        }
    }
    $support->log_stamped("\nDone with chromosome $chr.\n", 1);
}
$support->log_stamped("\nDone.\n");


# finish logfile
$support->finish_log;

