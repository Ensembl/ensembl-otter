#!/usr/local/bin/perl

=head1 NAME

add_ensembl_mappings.pl - adds xrefs to ensembl transcripts

=head1 SYNOPSIS

add_ensembl_mappings.pl [options]

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

    --prune                             reset to the state before running this
                                        script

=head1 DESCRIPTION

This script extracts xrefs from an ensembl database that link OTT and ENST transcripts.
For each pair of transcripts, the 'best' type is then added to Vega as an xref.

Identify where a Vega transcript matches to more than one Ensembl one by:

   $ grep 'matches to multiple Ensembl transcripts' my_log.log

WARNINGS indicate where a Vega transcript used in Ensembl is no longer present in Vega,
and also other problems such as failure to store an xref in the db for whatever reason

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

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
use Data::Dumper;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
    'chromosomes|chr=s@',
    'gene_stable_id|gsi=s@',
    'ensemblhost=s',
    'ensemblport=s',
    'ensembluser=s',
    'ensemblpass=s',
    'ensembldbname=s',
    'prune',
);
$support->allowed_params(
    $support->get_common_params,
    'chromosomes',
    'gene_stable_id',
    'ensemblhost',
    'ensemblport',
    'ensembluser',
    'ensemblpass',
    'ensembldbname',
    'prune',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('chromosomes');

# ask user to confirm parameters to proceed
$support->confirm_params;


# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect databases and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $ta = $dba->get_TranscriptAdaptor();
my $ea = $dba->get_DBEntryAdaptor();
#ensembl db
my $edba = $support->get_database('ensembl','ensembl');
my $esa  = $edba->get_SliceAdaptor();

# delete all ensembl xrefs if --prune option is used
if (!$support->param('dry_run')) {
	if ($support->param('prune') and $support->user_proceed("Would you really like to delete all previously added ENST xrefs before running this script?")) {
		my $num;
		# xrefs
		$support->log("Deleting all ensembl_id xrefs...\n");
		$num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name like \'ENST%\'
		));
		$support->log("Done deleting $num entries.\n");

		# object_xrefs
		$support->log("Deleting orphan object_xrefs...\n");
		$num = $dba->dbc->do(qq(
           DELETE ox
           FROM object_xref ox
           LEFT JOIN xref x ON ox.xref_id = x.xref_id
           WHERE x.xref_id IS NULL
        ));
		$support->log("Done deleting $num entries.\n");
	}
}
elsif ($support->param('prune')){
	$support->log("Not deleting any xrefs since this is a dry run.\n");
}
	
my @gene_stable_ids = $support->param('gene_stable_id');
my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;

#get xrefs from E! db for wanted chromosomes

my $ens_ids;
CHR:
foreach my $slice (@{$esa->fetch_all('toplevel')}) {
	my $chr_name = $slice->seq_region_name;
	next CHR if ($chr_name =~ /^NT|MT/);
	$support->log("Retrieving Ensembl genes from chromosome $chr_name...\n");		
 GENE:
	foreach my $g (@{$slice->get_all_Genes()}) {
		next GENE unless ($g->analysis->logic_name =~ /havana/);
		foreach my $t (@{$g->get_all_Transcripts}) {
			my $tsi = $t->stable_id;
		XREF:
			foreach my $x (@{$t->get_all_DBEntries}){
				my $dbname = $x->dbname;
				my $name = $x->display_id;
				next XREF unless ($dbname =~ /OTTT/);
				next XREF unless ($name =~ /OTT/);

				$ens_ids->{$name}{$tsi}{$dbname}++;
			}
		}
	}
#	last;
}

warn Dumper($ens_ids);

my $external_db;

#this defines the order in which the e! xrefs will be used, and which external_db 
#they match in Vega
my @priorities = qw(shares_CDS_and_UTR_with_OTTT:ENST_ident
					shares_CDS_with_OTTT:ENST_CDS
					OTTT:ENST_ident);

#add xrefs to each 
foreach my $v_id (keys %$ens_ids) {
	my $transcript = $ta->fetch_by_stable_id($v_id);
	unless ($transcript) {
		$support->log_warning("Can't retrieve transcript $v_id from Vega\n");
		next;
	}
	$support->log("Studying transcript $v_id\n");
	my @c = ();
	while ( my ($e_id, $xrefs) =  each %{$ens_ids->{$v_id}} ) {
		push @c, $e_id;
		my $found = 0;
		foreach my $db (@priorities) {
			my ($edb,$vdb) = split ':',$db;
			last if $found;
			if ($xrefs->{$edb}) {
				my $dbentry = Bio::EnsEMBL::DBEntry->new(
					-primary_id => $e_id,
					-display_id => $e_id,
					-version    => 1,
					-release    => 1,
					-dbname     => $vdb,
				);
				$transcript->add_DBEntry($dbentry);
				if ($support->param('dry_run')) {
					$support->log("Would store $vdb xref $e_id for transcript $v_id.\n", 1);
					$found = 1;
				}
				else {
					my $dbID = $ea->store($dbentry, $transcript->dbID, 'transcript');
		
					# apparently, this xref had been stored already, so get
					# xref_id from db
					unless ($dbID) {
						my $sql = qq(
                         SELECT x.xref_id
                         FROM xref x, external_db ed
                         WHERE x.external_db_id = ed.external_db_id
                         AND x.dbprimary_acc = '$e_id'
                         AND ed.db_name = '$vdb'
                         );
						($dbID) = @{ $dbh->selectall_arrayref($sql) || [] };
						$support->log_verbose
					}
					if ($dbID) {
						$support->log("Stored $vdb xref $e_id for transcript $v_id.\n", 1);
						$found = 1;
					} else {
						$support->log_warning("No dbID for $vdb xref ($e_id) transcript $v_id\n", 1);
					}
				}
			}
		}
	}
	if (scalar(@c) > 1) {
		my $ids = join ' ',@c;
		$support->log("Vega transcript $v_id matches to multiple Ensembl transcripts: $ids\n");
	}
}

$support->finish_log;
