#!/usr/local/bin/perl

=head1 NAME

patch_mouse_WU_genes.pl

=head1 SYNOPSIS

patch_mouse_WU_genes.pl [options]

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

    -name_file=FILE                     read stable IDs from file

=head1 DESCRIPTION

Update name, source, and analysis_id of WU genes from info in a file

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use FindBin qw($Bin);
use vars qw( $SERVERROOT );

BEGIN {
    $SERVERROOT = "$Bin/../../../..";
    unshift @INC,"$SERVERROOT/bioperl-live";
    unshift @INC,"$SERVERROOT/ensembl/modules";
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Data::Dumper;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
$support->parse_common_options(@_);
$support->parse_extra_options(
    'gene_name_file=s');
$support->allowed_params(
	$support->get_common_params,
	'gene_name_file');
$support->check_required_params('gene_name_file');	
if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}
$support->confirm_params;
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $ga = $dba->get_GeneAdaptor;
my $ta = $dba->get_TranscriptAdaptor;

#get analysis_id for external genes;
my $a_sth = $dbh->prepare(qq(select analysis_id from analysis where logic_name = 'otter_external'));
$a_sth->execute;
#my $analysis_id;
my ($analysis_id) = $a_sth->fetchrow_array;

#get author attribute_type_ids and set values;
my $au_sth = $dbh->prepare(qq(select attrib_type_id from attrib_type where code = 'author'));
$au_sth->execute;
my ($author_id) = $au_sth->fetchrow_array;
my $author_value = 'Washu';
my $aumail_sth = $dbh->prepare(qq(select attrib_type_id from attrib_type where code = 'author_email'));
$aumail_sth->execute;
my ($author_email_id) = $aumail_sth->fetchrow_array;
my $author_email_value = 'jspieth@watson.wust';

unless ($author_id && $author_email_id) {
	$support->log_warning("Can't retrieve author ($author_id) or author_email ($author_email_id)\n");
	exit;
}

#sth for setting author_attributes
my $ga_sth = $dbh->prepare(qq(update gene_attrib set value = ? where attrib_type_id = ? and gene_id = ?));
my $ta_sth = $dbh->prepare(qq(update transcript_attrib set value = ? where attrib_type_id = ? and transcript_id = ?));

#sth for setting display_xref
my $gdx_sth = $dbh->prepare(qq(update xref x, gene g set x.display_label = ? where g.display_xref_id = x.xref_id and g.gene_id = ?));
my $tdx_sth = $dbh->prepare(qq(update xref x, transcript t set x.display_label = ? where t.display_xref_id = x.xref_id and t.transcript_id = ?));

# read gene name file
my $gnamefile = $support->param('gene_name_file');
open(GNAMES, "< $gnamefile")
	or $support->throw("Couldn't open $gnamefile for reading: $!\n");
my $c;
while (my $gsi = <GNAMES>) {
	chomp($gsi);
	next unless ($gsi =~ /^OTTMUS/);
	next unless (my $gene = $ga->fetch_by_stable_id($gsi));

	my $g_dbID = $gene->dbID;
	my $old_name = $gene->display_xref->display_id;
	$c++;
	$support->log("$c. Studying gene $gsi ($old_name)...\n");
	
	#update gene object
	my $new_name = ($old_name =~ /^WU:/) ? $old_name : 'WU:'.$old_name;
	$support->log("...patch to $new_name\n",1);

	$gene->source('WU');
	$gene->analysis->dbID($analysis_id);
	if (! $support->param('dry_run') ) {
		$ga->update($gene);
		$gdx_sth->execute($new_name,$g_dbID);
		$ga_sth->execute($author_value,$author_id,$g_dbID);
		$ga_sth->execute($author_email_value,$author_email_id,$g_dbID);
	}

 TRANS:
	foreach my $trans (@{$gene->get_all_Transcripts}) {
		my $tsi = $trans->stable_id;
		my $t_dbID = $trans->dbID;
		my $old_tname = $trans->display_xref->display_id;
		my $new_tname = ($old_tname =~ /^WU:/) ? $old_tname : 'WU:'.$old_tname;
	
		#update transcript object
		$trans->analysis->dbID($analysis_id);
		if (! $support->param('dry_run') ) {
			$ta->update($trans);
			$tdx_sth->execute($new_tname,$t_dbID);
			$ta_sth->execute($author_value,$author_id,$t_dbID);
			$ta_sth->execute($author_email_value,$author_email_id,$t_dbID);
		}
	}
}

$support->finish_log;


