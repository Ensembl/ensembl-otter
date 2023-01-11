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

change_analysis_by_stable_id.pl - change the analysis of genes and transcripts

=head1 SYNOPSIS

change_analysis_by_stable_id.pl [options]

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

    --infile=FILE                       read list of stable IDs from FILE
    --logic_name=NAME                   change analysis to logic_name NAME
    --find_missing                      print list of genes in infile but not in
                                        database
    --outfile                           write list of missing genes to FILE

=head1 DESCRIPTION

This script reads a list of gene stable IDs from a file and sets the analysis
for these genes to the logic_name provided. It then sets the analysis_ids of all
transcripts to be the same as the parent genes (cannot cope with a single gene having
multiple transcripts with different analysis_ids).


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
  $SERVERROOT = "$Bin/../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::EnsEMBL::Analysis;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'infile=s',
  'logic_name=s',
  'outfile=s',
  'find_missing',
);
$support->allowed_params(
  $support->get_common_params,
  'infile',
  'logic_name',
  'outfile',
  'find_missing',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# check required params
$support->check_required_params(qw(infile logic_name));

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
our $dbh = $dba->dbc->db_handle;

# read list of stable IDs to keep or delete
my ($gene_stable_ids) = &read_infile($support->param('infile'));

# sanity check: check if all genes in the list are also in the database
&check_missing($gene_stable_ids);

# nothing else to be done for dry runs
if ($support->param('dry_run')) {
  $support->log("Nothing else to be done for dry run. Aborting.\n");
  exit(0);
}

# change analysis of gene and transcripts
&change_analysis($gene_stable_ids);

# finish logfile
$support->finish_log;


### END main ###


=head2 read_infile

  Arg[1]      : String $infile - name of file to read stable IDs from
  Example     : my ($gene_stable_ids) = &read_infile('/my/input/file.txt');
  Description : read list of stable IDs from file
  Return type : Arrayref - listref of stable IDs
  Exceptions  : none
  Caller      : internal

=cut

sub read_infile {
  my $infile = shift;

  $support->log_stamped("Reading stable IDs from file...\n");

  my $in = $support->filehandle('<', $infile);
  my @gene_stable_ids = ();
  while (<$in>) {
    chomp;
    if ($_ =~ /^OTT...G/) {
      push @gene_stable_ids, $_;
    }
  }
  close($in);
  $support->log_stamped("Done reading ".scalar(@gene_stable_ids)." genes, \n\n");
  return \@gene_stable_ids;
}

=head2 check_missing

  Arg[1]      : Arrayref $gene_stable_ids - listref of gene stable IDs
  Example     : &check_missing($gene_stable_ids);
  Description : Check if all genes in the list are also in the database. Warn if
                this is not the case, and print list of missing stable IDs on
                request (use --find_missing and --outfile options).
  Return type : none
  Exceptions  : none
  Caller      : general

=cut

sub check_missing {
  my $gene_stable_ids = shift;

  $support->log("Checking for missing genes...\n");

  # genes
  my $gsi_string = join("', '", @{ $gene_stable_ids });
  my $sql = qq(
        SELECT  stable_id
        FROM    gene
        WHERE   stable_id IN ('$gsi_string')
    );
  my @genes_in_db = map { $_->[0] } @{ $dbh->selectall_arrayref($sql) || [] };
  my $gdiff = scalar(@{ $gene_stable_ids }) - scalar(@genes_in_db);

  if ($gdiff) {
    $support->log_warning("Not all genes in the input file could be found in the db ($gdiff genes missing).\n");
    # print list of missing stable IDs
    if ($support->param('find_missing')) {
      $support->log("Printing list of missing stable IDs to file...\n", 1);
      my $out = $support->filehandle('>', $support->param('outfile'));

      # genes
      my %gseen;
      @gseen{@genes_in_db} = (1) x @genes_in_db;
      foreach my $gsi (@{ $gene_stable_ids }) {
	print $out "$gsi\n" unless $gseen{$gsi};
      }

      $support->log("Done.\n", 1);

      # suggest to run with --find_missing option
    } else {
      $support->log("Please run the script with the --find_missing option and check to see what's wrong.\n");
    }

    # ask user if he wants to proceed regardless of the potential problem
    unless ($support->user_proceed("\nPotential data inconsistencies (see logfile). Would you like to proceed anyway?")) {
      exit(0);
    }
  }
  $support->log("Done.\n\n");
}

=head2 change_analysis

  Arg[1]      : Arrayref $gene_stable_ids - listref of gene stable IDs
  Example     : &change_analysis($gene_stable_ids);
  Description : Change analysis of all genes in the list. An appropriate
                analysis is stored if it's not already there (logic_name taken
                from --logic_name option)
  Return type : none
  Exceptions  : thrown if problem storing analysis found
  Caller      : internal

=cut

sub change_analysis {
  my $gene_stable_ids = shift;

  if (!$gene_stable_ids or ref($gene_stable_ids) ne 'ARRAY') {
    $support->log_error("You must provide a list of stable IDs\n");
  }

  # add analysis
  $support->log("Adding analysis...\n");
  my $analysis = new Bio::EnsEMBL::Analysis (
    -program     => "change_analysis_by_stable_id.pl",
    -logic_name  => $support->param('logic_name'),
  );
  my $analysis_id = $dba->get_AnalysisAdaptor->store($analysis);
  $support->log_error("Couldn't store analysis ".$support->param('analysis').".\n") unless $analysis_id;
  $support->log("Done.\n\n");

  # change analysis for genes in list
  $support->log("Updating analysis of genes in list...\n");
  my $gsi_string = join("', '", @{ $gene_stable_ids });
  my $num = $dbh->do(qq(
        UPDATE gene g
        SET analysis_id = $analysis_id
        WHERE g.stable_id in ('$gsi_string')
    ));
  $support->log("Done updating $num genes.\n\n");

  #change analysis_ids of transcripts
  if ($support->user_proceed("\nSet all transcript analysis_ids to equal those of their genes ?")) {	
    $support->log("Updating analysis of corresponding transcripts...\n");
    $dbh->do(qq(
            UPDATE transcript t, gene g
            SET t.analysis_id = g.analysis_id
            WHERE g.gene_id = t.gene_id
        ));
    $support->log("Done updating transcripts.\n\n");
  }
  else {
    $support->log("Transcripts analysis_ids not updated.\n\n");
  }
}

