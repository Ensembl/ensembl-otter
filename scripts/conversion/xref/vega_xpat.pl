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

vega_xpat.pl - script to add Zebrafish expression patterns

=head1 SYNOPSIS

vega_xpat.pl [option]

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
    -h, --help, -?                      print help (this message)
    --prune=1                           delete previous entries (for reruns)


Specific options:

    --genbank_file=FILE                 ZFIN genbank file (from http://zfin.org/downloads/genbank.txt)
    --xpat_file=FILE                    ZFIN xpat file (from http://zfin.org/downloads/xpat_fish.txt)
    --outputdir=PATH                    Directory where script should write its output files (defaults to log dir)

=head1 DESCRIPTION

Add zebrafish expression pattern xrefs.
(i) Compares accessions in downloaded files to dna_align_features, identifiying genes that are overlapped by the features
(ii) Also identifies genes from Zfin record directly
Where the two overlap then adds xrefs


=head1 AUTHOR

Dan Sheppard <ds23@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut


use strict;
use warnings;
no warnings 'uninitialized';

use Storable;
use LWP::UserAgent;
use Data::Dumper;
use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift(@INC, "$SERVERROOT/ensembl/modules");
  unshift(@INC, "$SERVERROOT/bioperl-live");
  unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
}

use Bio::EnsEMBL::Utils::VegaCuration::Gene;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::VegaCuration::Gene($SERVERROOT);

$support->parse_common_options(@_);
$support->parse_extra_options(
  'genbank_file=s',
  'xpat_file=s',
  'prune',
);
$support->allowed_params(
  $support->get_common_params,
  'genbank_file',
  'xpat_file',
  'prune',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

my $min_perc_ident = 97;
my $min_hit_length = 150;

$support->confirm_params;
$support->init_log;

my $dba  = $support->get_database('ensembl');
my $dbh  = $dba->dbc->db_handle;
my $ga   = $dba->get_GeneAdaptor();
my $dafa = $dba->get_DnaAlignFeatureAdaptor();
my $ea   = $dba->get_DBEntryAdaptor();

# Prune
if($support->param("prune") and $support->user_proceed('Would you really like to delete zin_xpats from previous runs of this script?')) {
  $dbh->do("delete xref from xref join external_db using (external_db_id) where db_name = 'ZFIN_xpat'");
}

my (%est2accession,%genes2accession);

#download direct or read from file
my $urls = {
  genbank => 'http://zfin.org/downloads/genbank.txt',
  xpat    => 'http://zfin.org/downloads/xpat_fish.txt',
};

my $ua = LWP::UserAgent->new;
$ua->proxy(['http'], 'http://webcache.sanger.ac.uk:3128');

# get ZFIN genbank records
my $resp = $ua->get($urls->{'genbank'});
my $page = $resp->content;
if ($page) {
  $support->log("Genbank file downloaded from ZFIN\n");
}
else {
  $support->log("Unable to download Genbank file from ZFIN, trying to read from disc: ".$support->param('genbank_file')."\n",1);
  open (NOM, '<', $support->param('genbank_file')) or $support->throw(
    "Couldn't open ".$support->param('genbank_file')." for reading: $!\n");
  $page = do { local $/; <NOM> };
}
my @recs = split "\n", $page;
foreach (@recs) {
  my ($zfin_est_id, $so, undef, $accession) = split(/\t/, $_);
  next unless $zfin_est_id =~ m/^ZDB-EST-/ || $zfin_est_id =~ m/^ZDB-CDNA-/;
  $est2accession{$zfin_est_id} = $accession;
}

# Read in ZFIN Gene IDs having expression patterns and associated EST ID
my ($count_xpat_no_est,$count_xpat_est) = (0,0);
$resp = $ua->get($urls->{'xpat'});
$page = $resp->content;
if ($page) {
  $support->log("xpat file downloaded from ZFIN\n");
}
else {
  $support->log("Unable to download xpat file from ZFIN, trying to read from disc: ".$support->param('xpat_file')."\n",1);
  open (NOM, '<', $support->param('xpat_file')) or $support->throw(
    "Couldn't open ".$support->param('xpat_file')." for reading: $!\n");
  $page = do { local $/; <NOM> };
}
@recs = split "\n", $page;
foreach (@recs) {
  my ($zfin_gene_id, undef, $zfin_est_id, undef, undef, undef) = split(/\t/, $_);
  if (!$zfin_est_id) {
    $count_xpat_no_est++;
  }
  elsif (!$est2accession{$zfin_est_id}) {
    if ($support->param('verbose')) {
      $support->log_warning("No accession for zfin EST ID $zfin_est_id\n");
    }
  }
  else {
    $count_xpat_est++;
    $genes2accession{$zfin_gene_id}{$est2accession{$zfin_est_id}} = 1;
  }
}

if ($support->param('verbose')) {
  $support->log("Genes with ESTs are ".Dumper(\%genes2accession)."\n");
}

$support->log("Expression patterns without an EST ID: $count_xpat_no_est\n",2);
$support->log("Expression patterns with an EST ID: $count_xpat_est\n\n",2);

# Link ZFIN Gene IDs to ESTs and to genes via associated EST dna_align_features
$support->log("Looking for links between Genbank EST dna_align_features and genes they overlap...\n",1);
my %zfin_gene2vega_gene;
my $count_progress;
foreach my $zfin_gene_id (keys %genes2accession) {
  foreach my $est_accession (keys %{$genes2accession{$zfin_gene_id}}) {
    # Get all EST hits
    my $features = $dafa->generic_fetch("daf.hit_name LIKE '$est_accession%'");
    foreach my $feature (@$features) {
      # Does feature meet minimum critera?
      if ($feature->percent_id >= $min_perc_ident && ($feature->hend - $feature->hstart >= $min_hit_length) ) {
        # Get all genes that overlap this hit
        my $genes = $ga->fetch_all_by_Slice($feature->feature_Slice);
        foreach my $gene (@$genes) {
          $zfin_gene2vega_gene{$zfin_gene_id}{$gene->stable_id} = 1;
        }
      }
    }
  }
  $count_progress++;
  $support->log_verbose("Done $count_progress ZFIN Gene IDs)\n",2);
}

if ($support->param('verbose')) {
  $support->log("Genes with ESTs are ".Dumper(\%zfin_gene2vega_gene),1);
}
$support->log('ZFIN Gene IDs with expression patterns: ' . scalar keys(%genes2accession) . "\n",2);
$support->log('ZFIN Gene IDs with expression patterns linked to genes by ESTs: ' . scalar keys(%zfin_gene2vega_gene) . "\n\n",2);


$support->log("Looking for ZFIN genes in the download that can be linked to Vega by ZFIN xrefs...\n",1);
# Get gene stable_ids that have ZFIN xrefs
my $ary_ref = $dbh->selectall_arrayref("
	SELECT g.stable_id, x.dbprimary_acc, x.display_label
	FROM gene g, object_xref ox, xref x, external_db ed
	WHERE g.gene_id=ox.ensembl_id
	AND ox.ensembl_object_type='Gene'
	AND ox.xref_id=x.xref_id
	AND x.external_db_id=ed.external_db_id
	AND ed.db_name='ZFIN_ID'
");
my %xref_gene2ensgene;
my %zfin_gene_id2display_label;
foreach (@$ary_ref) {
  my ($gene_stable_id, $zfin_gene_id, $display_label) = @{$_};
  $xref_gene2ensgene{$zfin_gene_id}{$gene_stable_id} = 1;
  $zfin_gene_id2display_label{$zfin_gene_id} = $display_label;
}
# Count number of genes in download that have xrefs
my $count_xref = 0;
foreach my $zfin_gene_id (keys %genes2accession) {
  $count_xref++ if scalar keys %{$xref_gene2ensgene{$zfin_gene_id}};
}
$support->log("ZFIN Gene IDs with expression patterns that can be linked to Vega genes by xrefs: $count_xref\n\n",2),;

# Identify ZFIN Gene IDs linked to Vega genes by both ESTs and xrefs - need to ensure that both methods are consistent
$support->log("Ensuring links are supported by both Zfin xrefs and overlapping ESTs...\n",1);
my %est_xref_gene2ensgene;
foreach my $zfin_gene_id (keys %genes2accession) {
  next unless scalar keys %{$zfin_gene2vega_gene{$zfin_gene_id}};
  next unless scalar keys %{$xref_gene2ensgene{$zfin_gene_id}};
  # Both ZFIN Gene IDs have been mapped, but to the same gene?
  my %gene_stable_id;
  foreach my $gene_stable_id (keys %{$zfin_gene2vega_gene{$zfin_gene_id}}) {
    $gene_stable_id{$gene_stable_id}{'est'}++;
  }
  foreach my $gene_stable_id (keys %{$xref_gene2ensgene{$zfin_gene_id}}) {
    $gene_stable_id{$gene_stable_id}{'xref'}++;
  }
  # Check for gene stable_ids where mapped by both ESTs and xrefs
  foreach my $gene_stable_id (keys %gene_stable_id) {
    next if !$gene_stable_id{$gene_stable_id}{'est'} || !$gene_stable_id{$gene_stable_id}{'xref'};
    $est_xref_gene2ensgene{$zfin_gene_id}{$gene_stable_id} = 1;
  }
}
$support->log("ZFIN Gene IDs linked to Ensembl genes by ESTs and by xrefs: " . scalar keys(%est_xref_gene2ensgene) . "\n\n",2);


#not sure on purpose of this, but leave it in for now
my $output_dir = $support->param('logpath');
$output_dir =~ s|/$||;
if(!$support->param('dry_run')) {
  open(OUT, ">$output_dir/xpat.out") or die "Can't write to $output_dir/xpat.out: $!\n";
  foreach my $zfin_gene_id (keys %genes2accession) {
    print OUT "$zfin_gene_id";
    foreach my $est_accession (keys %{$genes2accession{$zfin_gene_id}}) {
      print OUT "\t$est_accession";
    }
    foreach my $gene_stable_id (keys %{$zfin_gene2vega_gene{$zfin_gene_id}}) {
      print OUT "\test:$gene_stable_id|$zfin_gene2vega_gene{$zfin_gene_id}{$gene_stable_id}";
    }
    foreach my $gene_stable_id (keys %{$xref_gene2ensgene{$zfin_gene_id}}) {
      print OUT "\txref:$gene_stable_id|$xref_gene2ensgene{$zfin_gene_id}{$gene_stable_id}";
    }
    print OUT "\n";
  }
  close OUT;
}

unless (scalar keys(%est_xref_gene2ensgene)) {
  $support->log_error("No mappings found, check what's changed - file format maybe ?\n");
}

$support->log("Storing xrefs...\n",1);
my $db = 'ZFIN_xpat';
my ($xref_c,%genes,%xpats);
foreach my $zfin_gene_id (keys %est_xref_gene2ensgene) {
  $xref_c++;
  my $display_id = join(';', sort keys %{$genes2accession{$zfin_gene_id}});
  my $dbentry = Bio::EnsEMBL::DBEntry->new(
    -primary_id => $zfin_gene_id,
    -display_id => $zfin_gene_id2display_label{$zfin_gene_id},
    -version    => 1,
    -dbname     => $db,
  );
  foreach my $gsi (keys %{$est_xref_gene2ensgene{$zfin_gene_id}}) {
    $genes{$gsi}++;
    $xpats{$zfin_gene_id}{$gsi}=1;
    my $gene = $ga->fetch_by_stable_id($gsi);
    $gene->add_DBEntry($dbentry);
    if (! $support->param('dry_run')) {
      my $dbID = $ea->store($dbentry, $gene->dbID, 'gene', 1);
    }
  }
  my $c = scalar keys(%{$xpats{$zfin_gene_id}});
  if ($c > 1) {
    $support->log("Zfin gene ID $zfin_gene_id attached to $c Vega genes\n",2);
  }
}

my $action = $support->param('dry_run') ? 'would be' : 'added';
$support->log("$xref_c distinct Xpat xrefs $action to " . keys(%genes) . " distinct genes\n",1);

$support->finish_log;

1;
