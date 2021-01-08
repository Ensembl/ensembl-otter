#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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

fix_transcript_names.pl - update transcript names to gene based ones, patch identical ones

=head1 SYNOPSIS

fix_transcript_names.pl [options]

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
    --prune                             remove changes from previous runs of this script

    --update                            update existing transcript names where gene names have changed

=head1 DESCRIPTION

This script updates vega transcript xrefs. When run with [update] it checks transcript
names against gene names and alters any that are not in sync. It's use in this mode is where
gene-based transcript names already exist but are now known to be wrong. This step will not
be needed for each release.

The more common use of this is script is to update transcript names from the original clone-name
based ones to gene-name based ones. This is done by running it without the [update] option. If
the option to fix duplicated names is chosen, then where the above patching of names results
in identical names for transcripts from the same gene, then the transcripts are numbered
incrementaly after ordering from the longest coding to the shortest non-coding.

The -prune option restores the data to the stage before this script was first run.


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
  unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::VegaCuration::Transcript;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::VegaCuration::Transcript($SERVERROOT);
### PARALLEL # $support ###

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'prune',
  'update',
  'live_update',
  'currentdbname=s',
  'currenthost=s',
  'currentport=s',
  'currentuser=s',
);
$support->allowed_params(
  $support->get_common_params,
  'prune',
  'update',
  'live_update',
  'currentdbname',
  'currenthost',
  'currentport',
  'currentuser',);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $sa  = $dba->get_SliceAdaptor;
my $aa  = $dba->get_AttributeAdaptor;
my $dbh = $dba->dbc->db_handle;
my $fix_names = 0;

my $dbname = $support->param('dbname');
my $n_flist_fh;
my ($c1,$c2,$c3) = (0,0,0);

### PRE # $fix_names # $c1 $c2 $c3 ###

if (! $support->param('update')) {

  #are duplicate transcript names going to be fixed later on ?
  if ($support->user_proceed("\nDo you want to check and fix duplicated transcript names?") ) {
    $fix_names = 1;
  }

  # make a backup tables the first time the script is run
  my @tables = qw(transcript xref transcript_attrib gene_attrib);
  my %tabs;
  map { $_ =~ s/`//g; $_ =~ s/$dbname.//g; $tabs{$_} += 1; } $dbh->tables;
  if (! exists ($tabs{'backup_ftn_transcript'})) {
    foreach my $table (@tables) {
      my $t = 'backup_ftn_'.$table;
      $support->log("Creating backup of $table\n\n");
      $dbh->do("CREATE table $t SELECT * FROM $table");
    }
  }

  if ($support->param('prune') && $support->user_proceed("\nDo you want to undo changes from previous runs of this script?")) {
    $support->log("Undoing changes from previous runs of this script...\n\n");
    foreach my $table (@tables) {
      my $t = 'backup_ftn_'.$table;
      $dbh->do("DELETE from $table");
      $dbh->do("INSERT into $table SELECT * FROM $t");
    }
  }
}

# which chromosomes do we study?
my @top_slices;
if ($support->param('chromosomes')) {
  foreach ($support->param('chromosomes')) {
    push @top_slices, $_;
  }
}
else {
  my $chr_length = $support->get_chrlength($dba,'','chromosome',1); #will retrieve non-reference slices
  foreach my $chr ($support->sort_chromosomes($chr_length)) {
    push @top_slices, $chr;
  }
}


if ($support->param('live_update')) {
  my $c_dba = $support->get_database('ensembl','current');
  $dba->dnadb($c_dba);
}


### SIZE # (\d+|X|Y)+ # 0.25 ###
### SIZE # # 0.05 ###
### RUN # @top_slices ###

$support->log("fix names = $fix_names\n");

foreach my $chrom_name (@top_slices) {
  my $chrom = $sa->fetch_by_region('toplevel',$chrom_name);

  $support->log_stamped("Checking chromosome $chrom_name\n");
 GENE:
  my ($genes) = $support->get_unique_genes($chrom,$dba);
  foreach my $gene (@$genes){
    my $gsi    = $gene->stable_id;
    my $transnames;
    my %seen_names;
    my %transcripts;
    my $g_name = $gene->get_all_Attributes('name')->[0]->value;
    $g_name = $gene->display_xref->display_id if ($support->param('update'));
    my $source = $gene->source;

    $support->log_verbose("\n$g_name ($gsi)\n");

    #check for identical names in loutre
    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      my $t_name = $trans->get_all_Attributes('name')->[0]->value;
      $t_name = $trans->display_xref->display_id if ($support->param('update'));

      #remove unexpected extensions but report them for fixing (should be caught by QC now but leave it here just in case)
      my $base_name = $t_name;
      if ( ($base_name =~ s/-\d{1,2}$//)
	|| ($base_name =~ s/__\d{1,2}$//)
        || ($base_name =~ s/__\d{1,2}$//)
        || ($base_name =~ s/_\d$//)
	|| ($base_name =~ s/\.\d+$//)) {
	unless ( ($support->param('dbname') =~ /rerio|zebrafish/) && ($chrom_name eq 'AB')) {
	  $support->log_warning("UNEXPECTED transcript name $t_name (".$support->param('dbname').",$chrom_name)\n");
	}
      }
			
      #warn duplicated names (should all be caught by the QC now)
      if (exists $seen_names{$base_name}) {
        $support->log_warning("IDENTICAL: $source gene $gsi ($g_name) has transcripts with identical base loutre names ($base_name), please fix\n");
      }
      else {
	$seen_names{$base_name}++;
	$transcripts{$t_name} = [$trans,$base_name];
      }
    }
		
    #patch names
  TRANS:
    foreach my $t_name (keys %transcripts) {
      my $trans = $transcripts{$t_name}->[0];
      my $base_name = $transcripts{$t_name}->[1];
      my $tsi    =  $trans->stable_id;
      my $t_dbID = $trans->dbID;		
      if ( ($t_name =~ /([\-\.]\d{3})$/) || ($t_name =~ /(\-\d{3})[_-]\d{1}$/) ) { #hack to patch dodgy names that haven't been fixed (esp Danio)
	my $new_name = "$g_name$1";
	push @{$transnames->{$new_name}}, "$t_name|$tsi";
	next if ($new_name eq $t_name);
	
        $c1++;

        #store a transcript attrib for the old name as long as it's not just a case change
        my $attrib = [
          Bio::EnsEMBL::Attribute->new(
            -CODE => 'synonym',
            -NAME => 'Synonym',
            -DESCRIPTION => 'Synonymous names',
            -VALUE => $t_name,
          )];
        unless (lc($t_name) eq lc($new_name)) {
          if (! $support->param('dry_run')) {
            $aa->store_on_Transcript($t_dbID, $attrib);
          }
	  $support->log_verbose("Stored synonym for old name ($t_name) for transcript $tsi\n",2);
        }

        #update xref for new transcript name
        if (! $support->param('dry_run')) {
          $dbh->do(qq(UPDATE xref x, external_db ed
                         SET x.display_label = "$new_name"
                       WHERE dbprimary_acc = "$tsi"
                         AND x.external_db_id = ed.external_db_id
                         AND ed.db_name = "Vega_transcript"
                    ));
        }
      $support->log(sprintf("%-20s%-3s%-20s", "$t_name", "--->", " $new_name")."\n", 1);
      }
      else {
        #log unexpected names (ie don't have -001 etc after removing Leo's extension
        $support->log_warning("Can't patch transcript $t_name ($tsi) because name is wrong\n");
      }
    }

    #if there are duplicated names in Vega then patch, add proper remark if they are fragmented
    if ( (grep { scalar(@{$transnames->{$_}}) > 1 } keys %{$transnames}) && $fix_names) {
      ($c2,$c3) = &check_remarks_and_update_names($gene,$c2,$c3);
    }
  }
}

### POST ###

$support->log("\nDone updating xrefs for $c1 transcripts\n");
$support->log("\nIdentified $c3 transcripts from $c2 genes as updatable.\n") if $fix_names;

### END ###

$support->finish_log;



=head2 check_remarks_and_update names

   Arg[1]     : B::E::Gene (with potentially duplicated transcript names)
   Arg[2]     : counter 1 (no. of patched genes)
   Arg[3]     : counter 2 (no. of patched transcripts)
   Example    : $support->update_names($gene,\$c1,\$c2)
   Description: - checks remarks and patches transcripts with identical names according to
                CDS and length
   Returntype : true | false (depending on whether patched or not), counter1, counter2

=cut

sub check_remarks_and_update_names {
  my ($gene,$gene_c,$trans_c) = @_;
  my $action = ($support->param('dry_run')) ? 'Would add' : 'Added';
  my $aa     = $gene->adaptor->db->get_AttributeAdaptor;
  my $dbh    = $gene->adaptor->db->dbc->db_handle;
  my $gsi    = $gene->stable_id;
  my $gid    = $gene->dbID;
  my $g_name;

  my $gene_remark = 'fragmented locus';
  my $attrib = [
    Bio::EnsEMBL::Attribute->new(
      -CODE => 'havana_cv',
      -NAME => 'Havana CV term',
      -DESCRIPTION => 'Controlled vocabulary terms from Havana',
      -VALUE => $gene_remark,
    ) ];

  eval {
    $g_name = $gene->display_xref->display_id;
  };	
  if ($@) {
    $g_name = $gene->get_all_Attributes('name')->[0]->value;
  }

  #get existing gene remarks
  my $remarks = [ map {$_->value} @{$gene->get_all_Attributes('remark')} ];

  #shout if there is no remark to identify this as being fragmented locus
  if ( ! grep {$_ eq 'fragmented locus' } @$remarks) {
    $support->log("Gene $g_name ($gsi) has duplicate transcript names but no fragmented_locus CV term, this will be added\n");
  }

  #add the correct gene remark if it's needed
  if ( grep {$_ eq $gene_remark } @$remarks) {
    $support->log_verbose("Gene $g_name ($gsi) - CV term regarding fragmentation of the locus already present\n");
  }
  else {
    $support->log("Gene $g_name ($gsi) - adding gene CV term regarding fragmentation of the locus\n",2);
    if (! $support->param('dry_run')) {
      $aa->store_on_Gene($gid,$attrib);
    }
  }

  ##patch transcript names according to length and CDS
  $gene_c++;

  #separate coding and non_coding transcripts
  my $coding_trans = [];
  my $noncoding_trans = [];
  foreach my $trans ( @{$gene->get_all_Transcripts()} ) {
    if ($trans->translate) {
      push @$coding_trans, $trans;
    }
    else {
      push @$noncoding_trans, $trans;
    }
  }

  #sort transcripts coding > non-coding, then on length
  my $c = 0;
  $support->log("Patching names according to CDS and length:\n",2);
  foreach my $array_ref ($coding_trans,$noncoding_trans) {
    foreach my $trans ( sort { $b->length <=> $a->length } @$array_ref ) {
      $trans_c++;
      my $tsi = $trans->stable_id;
      my $t_name;
      eval {
	$t_name = $trans->display_xref->display_id;
      };	
      if ($@) {
	$t_name = $trans->get_all_Attributes('name')->[0]->value;
      }
      $c++;
      my $ext = sprintf("%03d", $c);
      my $new_name = $g_name.'-'.$ext;
      $support->log(sprintf("%-20s%-3s%-20s", "$t_name ", "-->", "$new_name")."\n",1);
      if (! $support->param('dry_run')) {
	# update transcript display xref
	$dbh->do(qq(UPDATE xref x, external_db edb
                       SET x.display_label  = "$new_name"
                     WHERE x.external_db_id = edb.external_db_id
                       AND x.dbprimary_acc  = "$tsi"
                       AND edb.db_name      = "Vega_transcript"));
      }
    }
  }
  return ($gene_c,$trans_c);
}
