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

    --external_db=NAME                  use external_db NAME for xrefs (default is OTTT)
    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gene_stable_id, --gsi=LIST|FILE   only process LIST gene_stable_ids
                                        (or read list from FILE)
    --id_file=FILE                      file containing mappings between E! and vega transcripts
                                         - if not tab delimited then whitespace delimited
    --prune                             reset to the state before running this
                                        script (i.e. after running
                                        add_vega_xrefs.pl)

=head1 DESCRIPTION

This script parses a tab separated input file containing mappings between ensembl
and vega transcript IDs and adds the Ensembl IDs as xrefs. The external DB name can be specified
allowing the script to be used to add different types of xrefs.

[probably want to add the ability to query a database directly]

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
#use Bio::SeqIO::genbank;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
    'chromosomes|chr=s@',
    'gene_stable_id|gsi=s@',
	'id_file=s',
	'external_db=s',
 #   'ensemblhost=s',
 #   'ensemblport=s',
 #   'ensembluser=s',
 #   'ensemblpass=s',
 #   'ensembldbname=s',
    'prune',
);
$support->allowed_params(
    $support->get_common_params,
    'chromosomes',
    'gene_stable_id',
    'id_file',
	'external_db',
#    'ensemblhost',
#    'ensemblport',
#    'ensembluser',
#    'ensemblpass',
#    'ensembldbname',
    'prune',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('chromosomes');

# ask user to confirm parameters to proceed
$support->confirm_params;

# make sure add_vega_xrefs.pl has been run
exit unless $support->user_proceed("This script should be run after add_external_xrefs.pl. Have you run it?");

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors (caching features on one slice only)
# get an ensembl database for better performance (no otter tables are needed)
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa = $dba->get_SliceAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $ta = $dba->get_TranscriptAdaptor();
my $ea = $dba->get_DBEntryAdaptor();

# delete all ensembl_ids if --prune option is used; basically this resets
# xrefs to the state after running add_external_xrefs.pl
if (!$support->param('dry_run')) {
	if ($support->param('prune') and $support->user_proceed('Would you really like to delete all previously added ensembl_id xrefs before running this script?')) {
		my $num;
		# xrefs
		$support->log("Deleting all ensembl_id xrefs...\n");
		$num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name like 'ENST%'
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
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);

# parse input file
open (ID, '<', $support->param('id_file')) or $support->throw(
        "Couldn't open ".$support->param('id_file')." for reading: $!\n");
my $ens_ids;
while (<ID> ) {
	next if (/stable_id/);
	my ($e_id,$v_id) = split /\t/;
	($e_id,$v_id) = split / / unless ($e_id && $v_id);
	if ($e_id =~ /^OTT/) {
		my $t = $e_id;
		$e_id = $v_id;
		$v_id = $t;
	}
	chomp $v_id;
	chomp $e_id;
	if ( exists($ens_ids->{$v_id}) && ($e_id ne $ens_ids->{$v_id}) ) {
		my $prev_id = $ens_ids->{$v_id};
		eval {
			my $trans = $ta->fetch_by_stable_id($v_id);
			my $chr_name = $trans->seq_region_name;
			my $chr_start = $trans->seq_region_start;
			my $chr_end = $trans->seq_region_end;
			$support->log_warning("$v_id $chr_name:$chr_start:$chr_end matched to more than one Ensembl transcript ($e_id and $prev_id). Using the latter for xref mapping\n");
		};
		$support->log_warning("problem retrieving transcript $v_id - $@") if $@;
	}
	$ens_ids->{$v_id} = $e_id;
}

#check (user defined) external dbname
my $external_db = $support->param('external_db') || 'ENST';
my $sth = $dbh->prepare(qq(select * from external_db where db_name = ?));
$sth->execute($external_db);
unless (my @r = $sth->fetchrow_array) {
	$support->log_warning("External db name provided is not in the database, please check and add if neccesary\n");
	exit;
}

#retrieve transcripts and add xrefs
foreach my $v_id (keys %$ens_ids) {
	my $transcript = $ta->fetch_by_stable_id($v_id);
	unless ($transcript) {
		$support->log_warning("Can't retrieve transcript $v_id from Vega\n");
		next;
	}
	my $e_id       = $ens_ids->{$v_id};
	my $dbentry    = Bio::EnsEMBL::DBEntry->new(
					  -primary_id => $e_id,
					  -display_id => $e_id,
                      -version    => 1,
                      -release    => 1,
                      -dbname     => $external_db,
					);
	$transcript->add_DBEntry($dbentry);
	if ($support->param('dry_run')) {
		$support->log("Would store $external_db xref $e_id for transcript $v_id.\n", 1);
	} else {
		my $dbID = $ea->store($dbentry, $transcript->dbID, 'transcript');
		
		# apparently, this xref had been stored already, so get
		# xref_id from db
		unless ($dbID) {
			my $sql = qq(
                         SELECT x.xref_id
                         FROM xref x, external_db ed
                         WHERE x.external_db_id = ed.external_db_id
                         AND x.dbprimary_acc = '$e_id'
                         AND ed.db_name = '$external_db'
                         );
			($dbID) = @{ $dbh->selectall_arrayref($sql) || [] };
		}

		if ($dbID) {
			$support->log("Stored $external_db xref $e_id for transcript $v_id.\n", 1);
		} else {
			$support->log_warning("No dbID for $external_db xref ($e_id) transcript $v_id\n", 1);
		}
	}
}

$support->finish_log;
