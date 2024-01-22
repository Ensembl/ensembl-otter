#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
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

add_gene_synonyms.pl

=head1 SYNOPSIS

add_gene_synonyms.pl [options]

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

    -input_file=FILE                          read name changes from file

=head1 DESCRIPTION

quick script used to add synonyms for mouse genes with altered names (release 30)



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
    'input_file=s',);
$support->allowed_params(
	$support->get_common_params,
	'input_file',);
$support->check_required_params('input_file');	
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
my $aa = $dba->get_AttributeAdaptor;

#parse entries
my $inputfile = $support->param('input_file');
open(ID, "< $inputfile")
	or $support->throw("Couldn't open $inputfile for reading: $!\n");

#parse input file 
GENE:
while (<ID>) {
	my ($gsi,$syn) = split /\t/;
	next if ($gsi !~ /^OTT/);
	$gsi =~ s/ //g;
	chomp $syn;

	if (my $gene = $ga->fetch_by_stable_id($gsi)) {
		
		foreach my $existing_syn (@{$gene->get_all_Attributes('synonym')}) {
			if ($existing_syn->value eq $syn) {
				$support->log_warning("Not adding $syn synonym for gene $gsi since it already exists\n");
				next GENE;
			}
		}

		if ( lc($gene->display_xref->display_id) eq (lc($syn)) ) {
			$support->log_warning("Not adding $syn synonym for gene $gsi since it matches the existing gene name\n");
			next GENE;
		}
		
		my $attrib =  [
					Bio::EnsEMBL::Attribute->new(
						-CODE => 'synonym',
						-NAME => 'Synonym',
						-DESCRIPTION => 'Synonymous names',
						-VALUE => $syn,
					)];
		if (! $support->param('dry_run')) {
			$aa->store_on_Gene($gene->dbID, $attrib);
		}
		$support->log("Stored $syn synonym for gene $gsi\n");
	}
	else {
		$support->log_warning("Gene not recovered for $gsi ($syn)\n");
	}
	
}

$support->finish_log;
