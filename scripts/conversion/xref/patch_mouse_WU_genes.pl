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
my $sa  = $dba->get_SliceAdaptor;
my %sths;
$sths{'gene'}->{'adaptor'} = $dba->get_GeneAdaptor;
$sths{'trans'}->{'adaptor'} =  $dba->get_TranscriptAdaptor;

#get analysis_ids for external genes;
my $a_sth = $dbh->prepare(qq(select analysis_id from analysis where logic_name = ?));
$a_sth->execute('otter_external');
my ($wu_analysis_id) = $a_sth->fetchrow_array;
$a_sth->execute('otter');
my ($havana_analysis_id) = $a_sth->fetchrow_array;

#get author attribute_type_ids and set values for the WashU genes;
my $au_sth = $dbh->prepare(qq(select attrib_type_id from attrib_type where code = 'author'));
$au_sth->execute;
my ($author_id) = $au_sth->fetchrow_array;
my $wu_author_value = 'Washu';
my $havana_author_value = 'Havana';
my $aumail_sth = $dbh->prepare(qq(select attrib_type_id from attrib_type where code = 'author_email'));
$aumail_sth->execute;
my ($author_email_id) = $aumail_sth->fetchrow_array;
my $wu_author_email_value = 'jspieth@watson.wust';
my $havana_author_email_value = 'havana@sanger.ac.uk';

unless ($author_id && $author_email_id) {
	$support->log_warning("Can't retrieve author ($author_id) or author_email ($author_email_id)\n");
	exit;
}


#sth for setting author_attributes
$sths{'gene'}->{'attrib'} = $dbh->prepare(qq(update gene_attrib set value = ? where attrib_type_id = ? and gene_id = ?));
$sths{'trans'}->{'attrib'} = $dbh->prepare(qq(update transcript_attrib set value = ? where attrib_type_id = ? and transcript_id = ?));

#sth for setting display_xrefs
$sths{'gene'}->{'name'} = $dbh->prepare(qq(update xref x, gene g set x.display_label = ? where g.display_xref_id = x.xref_id and g.gene_id = ?));
$sths{'trans'}->{'name'} = $dbh->prepare(qq(update xref x, transcript t set x.display_label = ? where t.display_xref_id = x.xref_id and t.transcript_id = ?));

# read WU gene IDs file
my $washu_genes;
my $gnamefile = $support->param('gene_name_file');
open(GNAMES, "< $gnamefile")
	or $support->throw("Couldn't open $gnamefile for reading: $!\n");
my ($c1,$c2,$c3);
while (my $gsi = <GNAMES>) {
	chomp($gsi);
	next unless ($gsi =~ /^OTTMUS/);
	$washu_genes->{$gsi} = 1;
}

my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);
foreach my $chr (@chr_sorted) {
    $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");
	my $slice = $sa->fetch_by_region('chromosome', $chr);
	foreach my $gene (@{$slice->get_all_Genes()}) {
		next if ($gene->source eq 'KO');
		my $gsi = $gene->stable_id;

		#are we looking at a Washu gene (ie identified from otter sql) ?
		if ($washu_genes->{$gsi}) {
			my $g_dbID = $gene->dbID;
			my $old_name = $gene->display_xref->display_id;
			$c1++;
			$support->log("Studying WU gene $gsi ($old_name)...\n");
			my $new_name;
			if ($old_name =~ /^WU:/) {
				$support->log("...already a WU gene.\n",1);
			}
			else {
				$c2++;
				$new_name = 'WU:'.$old_name;
				$support->log("...patch to $new_name\n",1);

				#update gene object
				&update_details($gene,
								'WU',
								$wu_analysis_id,
								$new_name,
								$g_dbID,
								$wu_author_value,
								$author_id,
								$wu_author_email_value,
								$author_email_id);
				
				foreach my $trans (@{$gene->get_all_Transcripts}) {
					my $tsi = $trans->stable_id;
					my $t_dbID = $trans->dbID;
					my $old_tname = $trans->display_xref->display_id;
					my $new_tname = ($old_tname =~ /^WU:/) ? $old_tname : 'WU:'.$old_tname;
					&update_details($trans,
									'WU',
									$wu_analysis_id,
									$new_tname,
									$t_dbID,
									$wu_author_value,
									$author_id,
									$wu_author_email_value,
									$author_email_id);
				}
			}
		}

		#otherwise are Havana genes identified as Havana
		else {
			my $g_dbID = $gene->dbID;
			my $name = $gene->display_xref->display_id;
			if ($name =~ /^WU/) {				
				$c3++;
				$support->log("Patching gene $gsi ($name) to Havana...\n");
				$name =~ s/^WU://;
				&update_details($gene,
								'Havana',
								$havana_analysis_id,
								$name,
								$g_dbID,
								$havana_author_value,
								$author_id,
								$havana_author_email_value,
								$author_email_id);
				
				foreach my $trans (@{$gene->get_all_Transcripts}) {
					my $tsi = $trans->stable_id;
					my $t_dbID = $trans->dbID;
					my $tname = $trans->display_xref->display_id;
					$tname = s/^WU://;
					&update_details($trans,
									'Havana',
									$havana_analysis_id,
									$name,
									$t_dbID,
									$havana_author_value,
									$author_id,
									$havana_author_email_value,
									$author_email_id);
					
				}
			}
		}
	}
}

$support->log("Studied $c1 WU genes and updated $c2 from Havana to WashU. Also had to patch $c3 Havana genes from WU to Havana\n");
		
$support->finish_log;			


sub update_details {
	my ($obj,$source,$analysis_id,$new_name,$dbID,$author_value,$author_id,$author_email_value,$author_email_id) = @_;
	my $sth;
	if ($obj->isa('Bio::EnsEMBL::Gene')) {
		$sth = $sths{'gene'};
		$obj->source($source)
	}
	elsif ($obj->isa('Bio::EnsEMBL::Transcript')) {
		$sth = $sths{'trans'};
	}
	else { warn "what the !!!"; }

	$obj->analysis->dbID($analysis_id);
	if (! $support->param('dry_run') ) {
		$sth->{'adaptor'}->update($obj);
		$sth->{'name'}->execute($new_name,$dbID);
		$sth->{'attrib'}->execute($author_value,$author_id,$dbID);
		$sth->{'attrib'}->execute($author_email_value,$author_email_id,$dbID);
	}
}

