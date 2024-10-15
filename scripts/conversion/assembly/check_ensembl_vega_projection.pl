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

check_ensembl_vega_projection.pl - check for underlying sequence differences between annotation
                                   in vega and ensembl-vega

=head1 SYNOPSIS

    ./check_ensembl_vega_projection.pl
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

    --evegadbname=NAME                  ensembl-vega database NAME
    --evegahost=HOST                    ensembl-vega database host HOST
    --evegaport=PORT                    ensembl-vega database port PORT
    --evegauser=USER                    ensembl-vega database username USER
    --evegapass=PASS                    ensembl-vega database password PASS

    --ensembldbname=NAME                ensembl database NAME (for DNA sequence)
    --ensemblhost=HOST                  ensembl database host HOST
    --ensemblport=PORT                  ensembl database port PORT
    --ensembluser=USER                  ensembl database username USER
    --ensemblpass=PASS                  ensembla database password PASS

=head1 DESCRIPTION

Identify differences in cDNA and protein sequences between a Vega and an ensembl-vega database.


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
  unshift @INC,"$SERVERROOT/ensembl/modules";
  unshift @INC,"$SERVERROOT/bioperl-live";
}

use Bio::EnsEMBL::Utils::ConversionSupport;
use Pod::Usage;
use Fcntl;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
### PARALLEL # $support ###

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'chromosomes=s',
  'evegahost=s',
  'evegaport=s',
  'evegauser=s',
  'evegapass=s',
  'evegadbname=s',
  'ensemblhost=s',
  'ensemblport=s',
  'ensembluser=s',
  'ensemblpass=s',
  'ensembldbname=s',
  'ensemblassembly=s',
  'emboss_path=s',
  'wise2_path=s',
);

$support->allowed_params($support->get_common_params,
			 'chromosomes',
			 'evegahost',
			 'evegaport',
			 'evegauser',
			 'evegapass',
			 'evegadbname',
			 'ensemblhost',
			 'ensemblport',
			 'ensembluser',
			 'ensemblpass',
			 'ensembldbname',
                         'ensemblassembly',
			 'emboss_path',
			 'wise2_path',
		       );
if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

$support->init_log;

#get database adaptors
my $ev_dba = $support->get_database('ensembl','evega');
my $ev_sa  = $ev_dba->get_SliceAdaptor;
my $v_dba = $support->get_database('ensembl');
my $v_ga  = $v_dba->get_GeneAdaptor;

#add core db for dna
my $e_dba  =$support->get_database('ensembl','ensembl');
$ev_dba->dnadb($e_dba);

### PRE # # ###

# which chromosomes do we study?
$support->comma_to_list('chromosomes');
my @ev_top_slices;
if ($support->param('chromosomes')) {
  foreach ($support->param('chromosomes')) {
    push @ev_top_slices, $ev_sa->fetch_by_region("toplevel", $_);
  }
}
else {
  @ev_top_slices = sort { $a->seq_region_name() cmp $b->seq_region_name()} @{$ev_sa->fetch_all('chromosome',$support->param('ensemblassembly'),1,1)};
}

my @ev_names = map { $_->seq_region_name } @ev_top_slices;

### RUN # @ev_names ###

my $c=1;
foreach my $chrom_name (@ev_names) {
  my $ev_slice = $ev_sa->fetch_by_region(undef,$chrom_name);

#  next unless ($chrom_name =~ /X|Y|CHR_/);
  $support->log_stamped("\nExamining chromosome $chrom_name in ensembl-vega database\n");

  my ($ev_genes) = $support->get_unique_genes($ev_slice,$ev_dba);
  foreach my $ev_gene (@$ev_genes) {
    my $gsi = $ev_gene->stable_id;
    my $v_gene = $v_ga->fetch_by_stable_id($gsi);
    next GENE unless $v_gene;
    my $name = $ev_gene->display_xref->display_id;
    $support->log_verbose("Examining gene $gsi ($name)\n",1);
    my %trans = map {$_->stable_id, $_ } @{$v_gene->get_all_Transcripts()};
  TRANS:
    foreach my $ev_trans (  @{$ev_gene->get_all_Transcripts()} ) {
      my $tsi = $ev_trans->stable_id;
      my $v_trans = $trans{$ev_trans->stable_id};
      next TRANS unless $v_trans;
      $support->log_verbose("Examining transcript $tsi\n",1);
      my $ev_seq = $ev_trans->seq->seq;
      my $v_seq  = $v_trans->seq->seq;
      $ev_seq =~ s/[^CGATcgat]/N/g;
      $v_seq =~ s/[^CGATcgat]/N/g;
      if ($ev_seq ne $v_seq) {
	$support->log_warning("$c. Transcript sequence for ".$v_trans->stable_id." (gene $name) varies between Vega and Ensembl-vega:\n",2);
        my $cdna_alignment = $support->get_alignment(">Vega\n".$v_seq, ">Ens.\n".$ev_seq, 'DNA');
        $support->log($cdna_alignment,3);
	my $ev_transl = $ev_trans->translation;
	my $v_transl = $v_trans->translation;
	if ( $ev_transl && $v_transl ) {
	  my $ev_transl_seq = $ev_trans->translation->seq;
	  my $v_transl_seq = $v_trans->translation->seq;
	  if ($ev_transl_seq ne $v_transl_seq) {
	    $support->log_warning("$c. Translations for ".$v_trans->stable_id." also vary between Vega and Ensembl-vega:\n",2);
            if ($support->param('verbose')) {
              my $aa_alignment = $support->get_alignment(">Vega\n".$v_transl_seq, ">Ens.\n".$ev_transl_seq, 'PEP');
              $support->log($aa_alignment,3);
            }
	  }
	  else {
	    $support->log_verbose("$c. Translations for ".$v_trans->stable_id." do not differ\n");
	  }
	}
	elsif ( $ev_transl || $v_transl ) {
	  $support->log_warning("Only one of the transcripts for ".$v_trans->stable_id." translates, this is really really bad!\n");
	}
	else {
	  $support->log_verbose("$c. Transcript ".$v_trans->stable_id." is not protein coding\n",2);
	}
	$c++;
      }
    }
  }
}

$support->log("Done.\n");

### POST ###

# finish log
$support->finish_log;

### END ###
