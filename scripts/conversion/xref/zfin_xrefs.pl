#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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

zfin_xrefs.pl - adds gene xrefs for Zebrafish according to files downloaded from Zfin

=head1 SYNOPSIS

zfin_xrefs.pl [options]

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
    --prune                             reset to the state before running this
                                        script
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive                   run script interactively (default: true)
    -n, --dry_run, --dry                don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

    --zfin_name_file=FILE               File downloaded from Zfin (zfin.org/downloads/vega_transcript.txt)
                                        containing relationships between OTT transcript IDs and Zfin records
    --zfin_desc_file=FILE               File downloaded from Zfin (zfin.org/transfer/MEOW/zfin_genes.txt)
                                        containing Zfin descriptions of genes, plus some other names that could be used
                                        if any were mssing from vega_transcript.txt.
    --zfin_alias_file=FILE              File downloaded from Zfin (http://zfin.org/downloads/aliases.txt)
                                        containing other Zfin names

=head1 DESCRIPTION

Parses three input files from Zfin, adding Zfin xrefs, updating names, updating STATUS and adding aliases to a Vega database.
Details of genes that had names changed are dumped into zfish_changed_gene_names.txt - can be given to anacode if needed


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
use Storable;
use Encode qw(decode encode);

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::SeqIO::genbank;
use Data::Dumper;
use LWP::UserAgent;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'zfin_name_file=s',
  'zfin_desc_file=s',
  'zfin_alias_file=s',
  'prune',
);

$support->allowed_params(
  $support->get_common_params,
  'zfin_name_file',
  'zfin_desc_file',
  'zfin_alias_file',
  'prune',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->confirm_params;
$support->init_log;

my $dba = $support->get_database('ensembl');
my $ga  = $dba->get_GeneAdaptor();
my $sa  = $dba->get_SliceAdaptor();
my $ea  = $dba->get_DBEntryAdaptor();
my $aa  = $dba->get_AttributeAdaptor();

if ($support->param('prune') and $support->user_proceed('Would you really like to delete xrefs from previous runs of this script ?')) {
  my $num;

  #need code for descriptions, status, and synonyms adding if this is to be meaningfull

  # xrefs
  $num = $dba->dbc->do(qq(
           DELETE x
           FROM xref x, external_db ed
           WHERE x.external_db_id = ed.external_db_id
           AND ed.db_name = 'ZFIN_ID'));
  $support->log("Done deleting $num entries.\n");

  # object_xrefs
  $support->log("Deleting orphan object_xrefs...\n");
  $num = $dba->dbc->do(qq(
           DELETE ox
           FROM object_xref ox
           LEFT JOIN xref x ON ox.xref_id = x.xref_id
           WHERE x.xref_id IS NULL));
  $support->log("Done deleting $num entries.\n");

  #reset display xrefs
  $support->log("Resetting gene.display_xref_id...\n");
  $num = $dba->dbc->do(qq(
           UPDATE gene g, xref x
           SET g.display_xref_id = x.xref_id
           WHERE g.stable_id = x.dbprimary_acc
        ));
  $support->log("Done deleting $num entries.\n");
}

# statement handles for display_xref etc updates
my $sth_gene_dispxref = $dba->dbc->prepare("UPDATE gene SET display_xref_id = ? WHERE gene_id = ?");
my $sth_gene_desc     = $dba->dbc->prepare("UPDATE gene SET description = ? WHERE gene_id = ?");
my $sth_gene_status   = $dba->dbc->prepare("UPDATE gene SET status = 'KNOWN' WHERE gene_id = ?");
my $sth_trans_desc    = $dba->dbc->prepare("UPDATE transcript SET description = ? WHERE transcript_id = ?");

#try and download direct
my $urls = {
  alias    => 'http://zfin.org/downloads/aliases.txt',
  vegafile => 'http://zfin.org/downloads/vega_transcript.txt',
  zfinfile => 'http://zfin.org/transfer/MEOW/zfin_genes.txt',
};

my $ua = LWP::UserAgent->new;
$ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');
my (%aliases,%zfin,%otter_zfin_links,%crossrefs);

# get ZFIN aliases
my $resp = $ua->get($urls->{'alias'});
my $page = $resp->content;
if ($page) {
  $support->log("Alias file downloaded from ZFIN\n");
}
else {
  $support->log("Unable to download alias file from ZFIN, trying to read from disc: ".$support->param('zfin_alias_file')."\n",1);
  open (NOM, '<', $support->param('zfin_alias_file')) or $support->throw(
    "Couldn't open ".$support->param('zfin_alias_file')." for reading: $!\n");
  $page = do { local $/; <NOM> };
}
my @recs = split "\n", $page;
foreach (@recs) {
  chomp;
  next unless (/ZDB-GENE/);
  my ($zfinid,$desc,$name,$alias,$so) = split /\t/;
  $alias = encode('utf8',$alias);
  $aliases{$zfinid}->{$alias}++;
}

#get vega names
$resp = $ua->get($urls->{'vegafile'});
$page = $resp->content;
if ($page) {
  $support->log("Names downloaded from ZFIN\n");
}
else {
  $support->log("Unable to download Vega name file from ZFIN, trying to read from disc: ".$support->param('zfin_name_file')."\n",1);
  open (NOM, '<', $support->param('zfin_name_file')) or $support->throw(
    "Couldn't open ".$support->param('zfin_name_file')." for reading: $!\n");
  $page = do { local $/; <NOM> };
}
@recs = split "\n", $page;
foreach (@recs) {
  chomp;
  my ($zfinid,$so,$name,$ottid) = split /\s+/;
  $zfin{$zfinid}->{name} = $name;
  push @{$zfin{$zfinid}->{'vega_ids'}}, $ottid;
  $otter_zfin_links{$ottid} = $zfinid;
}

#get zfin descriptions
$resp = $ua->get($urls->{'zfinfile'});
$page = $resp->content;
if ($page) {
  $support->log("Descriptions downloaded from Zfin\n\n");
}
else {
  $support->log("Unable to download descriptions from ZFIN, trying to read from disc: ".$support->param('zfin_desc_file')."\n",1);
  open (NOM, '<', $support->param('zfin_desc_file')) or $support->throw(
    "Couldn't open ".$support->param('zfin_desc_file')." for reading: $!\n");
  $page = do { local $/; <NOM> };
}
@recs = split "\n", $page;
foreach (@recs) {
  chomp;
  my ($zfinid,$desc,$name,$lg,$pub) = split /\t/;
  if (exists $zfin{$zfinid}) {
    $zfin{$zfinid}->{desc} = $desc;
  }
  foreach my $alias (keys %{$aliases{$zfinid}}) {
    $zfin{$zfinid}->{'aliases'}{$alias}++;
  }

  #get any other names from description file
  my $newname;
  if ($name =~ /si\:(\S+)/) {
    $newname = lc($1);
  }
  elsif ($name =~ /(nitr\S+)\_/) {
    $newname = $1;
  }
  $crossrefs{$newname}->{zfinid} = $zfinid;
  $crossrefs{$newname}->{desc}   = $desc;
}

######################
# loop through genes #
######################

my $gene_count        = 0;
my $zfin_xref_added1  = 0;
my $zfin_xref_added2  = 0;
my $zfin_xref_missing = 0;
my $name_changed      = 0;
my @changed_names     = ("Stable ID\tnew name\tnew description");

my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);
foreach my $chr (@chr_sorted) {
  $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");

  # fetch genes from db
  $support->log("Fetching genes...\n");
  my $slice = $sa->fetch_by_region('chromosome', $chr);
  my $genes = $ga->fetch_all_by_Slice($slice);
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n");
  foreach my $gene(@$genes) {
    $gene_count++;
    my $gsi         = $gene->stable_id;
    my $gene_name   = $gene->display_xref->display_id;
    my $vega_g_desc = $gene->description;
    $support->log("Studying gene $gsi ($gene_name)\n",1); 

    my ($zfinid,$desc);
    foreach my $trans (@{$gene->get_all_Transcripts}) {
      my $tsi = $trans->stable_id;
      my $trans_name  = $trans->display_xref->display_id;
      my $vega_t_desc = $trans->description;
      if ( !$zfinid) {
        $zfinid = $otter_zfin_links{$tsi};
        $desc   = $zfin{$zfinid}->{'desc'};
        if ($zfinid) {
          $support->log("Getting zfin details for $gsi from $tsi\n",2)
        }
      }
      elsif ( $desc ne $zfin{$zfinid}->{'desc'}) {
        $support->log_warning("Descriptions for different transcripts of the same gene ($gsi,$gene_name) don't match - check vega_transcripts.txt\n",2);
      }
      if ($desc ne $vega_t_desc) {
        $support->log("Updating description for transcript $tsi ($trans_name)\n",3);
        if (! $support->param('dry_run')) {
          #execute sql to update transcript description
          $sth_trans_desc->execute($desc,$trans->dbID);
        }
      }
    }

    if ($zfinid) {
      $zfin_xref_added1++;
      my $new_name = $zfin{$zfinid}->{'name'};
      #excellent, update gene details
      &update_gene_details($gene,$zfinid,$new_name,$desc,$vega_g_desc);
    }
    else {
      $support->log_verbose("No Zfin name for $gsi ($gene_name) found, trying to match $gene_name with names in the zfin_genes.txt file\n",2);
      my $newname;
      # nitr cases
      if ($gene_name =~ /(nitr\S+)\_/) {
        $newname = $1;
      }
      # proper CH211-234G21.3 like names
      elsif ($gene_name =~ /\S+\-\d+\D+\d+\.\d+/) {
        $newname = lc($gene_name);
      }
      # improper dZ45H12.3 like names
      elsif ($gene_name =~ /(\D+\d+\D+\d+\.\d+)/) {
        my $name = $1;
        my ($prefix,$suffix) = ($name =~ /(\D+)(\d+\D+\d+\.\d+)/); 
        if ($prefix =~ /zKp/){
          $newname = "DKEYP-".$suffix;
        }
        elsif ($prefix =~ /zK/) {
          $newname = "DKEY-".$suffix;
        }
        elsif ($prefix =~ /zC/) {
          $newname = "CH211-".$suffix;
        }
        elsif ($prefix =~ /bZ/) {
          $newname = "RP71-".$suffix;
        }
        elsif ($prefix =~ /dZ/) {
          $newname = "BUSM1-".$suffix;
        }
        elsif (($prefix =~ /bY/)  || ($name =~ /BAC/) || ($name =~ /PAC/)) {
          $newname = "XX-".$name;
        }
        else {
          $newname = $name;
        }
      }
      else {
        $newname = $gene_name;
      }
      if (exists $crossrefs{$newname}) {
        #great, we can match this gene after all
        $zfin_xref_added2++;
        $support->log_warning("Matched vega record against zfin_genes.txt rather than vega_transcript.txt; have a word with Zfin\n",2);
        &update_gene_details($gene,$crossrefs{$newname}->{'zfinid'},$gene_name,$crossrefs{$newname}->{'desc'},$vega_g_desc);
      }
      else {
        #no match :-(
        $zfin_xref_missing++;
        $support->log_warning("Cannot match any zfin record (gene or transcript) with $gsi (vega_name = $gene_name; parsed vega_name = $newname)\n",2);
      }
    }
  }
}

#print changed gene names
open (OUT, '>'.$support->param('logpath').'/zfish_changed_gene_names.txt');
print OUT join "\n",@changed_names;


$support->log("Of $gene_count genes in total, $zfin_xref_added1 had a Zfin xref added from vega_transcript.txt, $zfin_xref_added2 had a Zfin xref added from zfin_genes.txt and $name_changed had a name change\n");
if ($zfin_xref_missing) {
  $support->log_warning("There are $zfin_xref_missing genes without Zfin xrefs, please check these out\n");
}

$support->finish_log;

sub update_gene_details {
  my ($gene,$zfinid,$zfin_name,$desc,$vega_g_desc) = @_;
  my $gsi       = $gene->stable_id;
  my $gene_name = $gene->display_xref->display_id;
  my $dbentry = Bio::EnsEMBL::DBEntry->new(-primary_id => $zfinid,
                                           -display_id => $zfin_name,
                                           -version    => 1,
                                           -dbname     => "ZFIN_ID",
                                         );
  $support->log("Adding Zfin xref for $gsi ($zfinid)\n",2);
  if ($zfin_name ne $gene_name) {
    $name_changed++;
    $support->log("Name for $gsi changed from $gene_name->$zfin_name. Storing old name as a synonym\n",2);
    my $attrib = [
      Bio::EnsEMBL::Attribute->new(
        -CODE        => 'synonym',
        -NAME        => 'Synonym',
        -DESCRIPTION => 'Synonymous names',
        -VALUE       => $gene_name,
      )];
    if (! $support->param('dry_run')) {
      $aa->store_on_Gene($gene->dbID, $attrib);
    }
  }
  foreach my $alias (keys %{$zfin{$zfinid}->{'aliases'}}) {
    $dbentry->add_synonym($alias);
    $support->log("Added xref synonym $alias to $gsi ($zfinid)\n",3);
  }
  $gene->add_DBEntry($dbentry);
  my $update_desc = 0;
  if ( ($desc ne $zfin_name) && ($desc ne $vega_g_desc) ) {
    $support->log("Updating description for $gsi '$vega_g_desc'->'$desc'\n",2);
    push @changed_names, "$gsi\t$zfin_name\t$desc";
    $update_desc = 1;
  }
  else {
    push @changed_names, "$gsi\t$zfin_name\t-";
  }
  if (! $support->param('dry_run')) {
    my $db_id = $ea->store($dbentry,$gene->dbID,'Gene') or die "Couldn't store entry\n";
    $sth_gene_dispxref->execute($db_id,$gene->dbID);
    if ($update_desc) {
      $sth_gene_desc->execute($desc,$gene->dbID);
    }
    $sth_gene_status->execute($gene->dbID);
  }
}
