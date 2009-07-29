#!/usr/local/bin/perl

=head1 NAME

cleanup_GD_genes.pl - identify CORF genes for deletion
                    - identify and delete redundant GD genes

=head1 SYNOPSIS

cleanup_GD_genes.pl [options]

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

    --chromosomes=LIST                  List of chromosomes to read (not working)
    --gd_delete=FILE                    file for stable IDs of GD genes to delete
                                        (defaults to GD_IDs_togo.txt)
    --corf_delete=FILE                  file for stable IDs of CORF genes to delete
                                        (defaults to corf_IDs_togo.txt)

=head1 DESCRIPTION

This script identifies all CORF genes in a Vega database and dumps stable IDs to
file for deletion. In addition it identifies GD genes that are overlapped by Havana
annotation as being ready for deletion. It must be run after the vega xrefs have
been set.

Logic is:

(i) retrieve each gene with a GD: prefix on its name (gene.display_xref)
(ii) if that gene has at least one transcript with a hidden_remark of 'corf',
or a remark that starts with the term 'corf', then identify is as CORF.

Reports on other GD: loci that have other remarks containing 'corf'.
Verbosely reports on non GD: loci that have remarks containing 'corf'.

(iii) examine all GD: genes to identify redundant ones - ie have an
overlapping Havana gene. Generate a file of stable IDs and use this to
delete the genes by calling delete_by_stable_id.pl

Verbosely report numbers of GD genes with a gomi remark (for jla1).

TO DO: Steps (ii) and (iii) could be combined to save (a little bit of)
run time ?

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <pm2@sanger.ac.uk>

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
  unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
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
  'chromosomes|chr=s@',
  'corf_delete=s',
  'gd_delete=s',
  'delete=s',
);
$support->allowed_params(
  $support->get_common_params,
  'chromosomes',
  'corf_delete',
  'gd_delete',
  'delete',
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

$support->comma_to_list('chromosomes');

#set paths and names for ID files and get filehandles
$support->param('corf_delete') || $support->param('corf_delete','corf_IDs_togo.txt');
$support->param('corf_delete',($support->param('logpath').$support->param('corf_delete')));
my $corf_outfile = $support->filehandle('>', $support->param('corf_delete'));
$support->param('gd_delete') || $support->param('gd_delete','GD_IDs_togo.txt');
$support->param('gd_delete',($support->param('logpath').$support->param('gd_delete')));
my $gd_outfile = $support->filehandle('>', $support->param('gd_delete'));

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;


#ask whether to automatically delete or not
my $delete_corf_genes = 0;
if ( (!$support->param('dry_run'))
       && ($support->user_proceed("\nDelete CORF genes ? (Warning - this can't be undone so if in doubt do later!)"))) {	
  $delete_corf_genes = 1;
}
my $delete_gd_genes = 0;
if ( (!$support->param('dry_run'))
       && ($support->user_proceed("\nDelete redundant GD genes ? (Warning - this can't be undone so if in doubt do later!)"))) {	
  $delete_gd_genes = 1;
}

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $ga  = $dba->get_GeneAdaptor;
my $sa  = $dba->get_SliceAdaptor;

#get chromosomes
my @chroms;
foreach my $chr ($support->sort_chromosomes) {
  push @chroms,  $sa->fetch_by_region('toplevel', $chr);
}

####################################################
# look at all Genes to identify corf / GD          #
####################################################

$support->log("Examining GD genes to identify CORFs and redundant annotation...\n");

#hashes for logging
my (%GD_to_delete,%GD_to_annotate,%corf_to_annotate,%corf);
my (%non_GD_hidden,%non_GD);
#more detailed logging if ever needed
my (%gomi_to_log_overlap,%gomi_to_log_no_overlap);
#counters
my $tot_gd;
my $tot_other_gd;

foreach my $slice (@chroms) {
  my $chr_name = $slice->seq_region_name;
  $support->log_stamped("\n\nLooping over chromosome $chr_name\n");
  my $genes = $slice->get_all_Genes;
  $support->log_stamped("Done fetching ".scalar @$genes." genes.\n");

 GENE:
  foreach my $gene (@$genes) {
    my $gsi = $gene->stable_id;
    my $name = $gene->display_xref->display_id;
    $tot_gd++ if ($name =~ /^GD:/);
    $support->log_verbose("Studying gene $gsi ($name) for remarks and name\n");
    my $found_corf_remark = 0;

    #get all remarks
    my (@hidden_remarks,@remarks);
    foreach my $trans (@{$gene->get_all_Transcripts()}) {
      my $tsi = $trans->stable_id;
      foreach my $remark ( @{$trans->get_all_Attributes('hidden_remark')} ) {
	push @hidden_remarks,$remark->value;
      }
      foreach my $remark ( @{$trans->get_all_Attributes('remark')} ) {
	push @remarks,$remark->value;
      }
    }

    #look for correctly formatted hidden remarks - these will be deleted if GD			
    if (grep {$_ =~ /^corf/i} @hidden_remarks ) {
      $found_corf_remark = 1;
      #capture CORF genes to delete later
      if ($name =~ /^GD:/) {
	$corf{$chr_name}->{$gsi} = $name;
      }
      #capture nonGD genes with the correct CORF remark
      else {
	$non_GD_hidden{$chr_name}->{$gsi} = $name;
      }			
    }

    #otherwise look for 'corf' type remarks
    if (! $found_corf_remark) {
      if (grep {$_ =~ /^corf/i} @remarks ) {
	#capture CORF genes with a remark that should be a corf hidden_remark
	if ( $name =~ /^GD:/ ) {
	  $support->log_warning("Deleting gene $gsi ($name) as CORF despite not having the properly formatted hidden_remark\n");
	  $corf{$chr_name}->{$gsi} = $name;
	}
	#capture non GD genes with a corf remark
	else {
	  $non_GD{$chr_name}->{$gsi} = $name;
	}
      }
    }									

    #look for overlap of GD with Havana.
    next GENE if ($name !~ /^GD:/);
    $tot_other_gd++ unless $corf{$chr_name}->{$gsi};
    $support->log_verbose("Studying GD gene $gsi ($name) for overlap with Havana\n");

    #get any overlapping Havana genes - defined by logicname of otter without a GD: name
    my $slice = $gene->feature_Slice;
    my $this_gene_strand = $gene->strand;
    my @genes = @{$slice->get_all_Genes('otter')};
    my $to_go = 0;
    foreach my $gene (@genes) {
      if ( ($gene->display_xref->display_id !~ /^GD:/)
	     && ( $gene->strand == 1 ) ){
	$to_go = 1;
      }
    }

    if ($to_go) {
      #if a GD gene overlaps Havana on the same strand then log its ID to delete it unless it's already been tagged as corf
      if (! $corf{$chr_name}->{$gsi}) {
	$GD_to_delete{$chr_name}->{$gsi} = $name;
      }
      #are there any gomi remarks ?
      if ( grep {$_ =~ /gomi/i} @hidden_remarks, @remarks ) {
	$gomi_to_log_overlap{$chr_name}->{$gsi} = $name;
      }
    }
    else {
      #if there's no overlap then log it as either corf or GD as priorities for annotation
      if ($corf{$chr_name}->{$gsi}) {
	$corf_to_annotate{$chr_name}->{$gsi} = $name;
      }
      else {
	$GD_to_annotate{$chr_name}->{$gsi} = $name;
      }
      #are there any gomi remarks ?
      if ( grep {$_ =~ /gomi/i} @hidden_remarks, @remarks ) {
	$gomi_to_log_no_overlap{$chr_name}->{$gsi} = $name;
      }
    }
  }
}


###########
# logging #
###########

my ($c1,$c2,$c3,$c4,$c5,$c6) = (0,0,0,0,0,0);

#report on GD genes that will be deleted as  CORF
$support->log_verbose("\nThe following CORF genes (ie GD with the correct CORF remark or hidden_remark) will be deleted:\n");
foreach my $chr (sort keys %corf) {
  $support->log_verbose("Chromosome $chr\n");
  foreach my $gsi (sort keys %{$corf{$chr}}) {
    $c1++;
    $support->log_verbose("$c1. $gsi (".$corf{$chr}->{$gsi}.")\n",1);
  }
}

#report on other GD genes that will be deleted
$support->log_verbose("\nThese other GD genes will be deleted since they are overlapped by Havana annotation\n");
foreach my $chr (sort keys %GD_to_delete) {
  $support->log_verbose("Chromosome $chr\n");
  foreach my $gsi (sort keys %{$GD_to_delete{$chr}}) {
    $c5++;
    $support->log_verbose("$c5. $gsi (".$GD_to_delete{$chr}->{$gsi}.")\n",1);
  }
}

#report on GD genes that will be deleted as  CORF
$support->log_verbose("\nThe following CORF genes do not overlap Havana and are priorities for reannotation:\n");
foreach my $chr (sort keys %corf_to_annotate) {
  $support->log_verbose("Chromosome $chr\n");
  foreach my $gsi (sort keys %{$corf_to_annotate{$chr}}) {
    $c2++;
    $support->log_verbose("$c2. $gsi (".$corf_to_annotate{$chr}->{$gsi}.")\n",1);
  }
}

#report on non GD genes with a hidden corf remark
#$support->log_verbose("\nThe following are non GD genes with a CORF hidden_remark:\n");
#foreach my $gsi (keys %non_GD_hidden) {
#  $c3++;
#	$support->log_verbose("$c3. $gsi (".$non_GD_hidden{$gsi}.")\n",1);
#}

#report on non GD genes with corf remark
#$support->log("\nThe following are non GD genes with a CORF remark:\n"); 
#foreach my $gsi (keys %non_GD) {
#  $c4++;
#  $support->log_verbose("$c4. $gsi (".$non_GD{$gsi}.")\n",1);
#}


$support->log_verbose("\nThese other GD genes will be kept since they do not overlap Havana annotation\n");
foreach my $chr (sort keys %GD_to_delete) {
  $support->log_verbose("Chromosome $chr\n");
  foreach my $gsi (sort keys %{$GD_to_annotate{$chr}}) {
    $c6++;
    $support->log_verbose("$c6. $gsi (".$GD_to_annotate{$chr}->{$gsi}.")\n",1);
  }
}

#summary
$support->log("\nThere are $tot_gd GD genes in total\n");
$support->log("There are $c1 CORF genes (ie with the correct CORF (hidden)remark) that would be deleted.\n");
$support->log("Of these $c1 CORF genes, $c2 don't overlap Havana so should be reannotated.\n",1);

#$support->log("There are $c3 non GD genes with a CORF style hidden_remark.\n");
#$support->log("There are $c4 non GD genes with the CORF style remark.\n");

$support->log("There are $tot_other_gd GD genes (excluding CORF) in total:\n");	
$support->log("$c5 of these overlap with Havana and will be deleted\n",1);
$support->log("$c6 of these do not overlap with Havana and are priorities for reannotation\n",1);


my $log_c_o  = scalar(keys %gomi_to_log_overlap);
my $log_c_no = scalar(keys %gomi_to_log_no_overlap);
$support->log_verbose("$log_c_no GD genes do not overlap Havana loci but do have a gomi remark\n");
$support->log_verbose("$log_c_o GD genes overlap Havana loci (and will be pruned from Vega) and have a gomi remark\n");

#create files to be used for deletion
foreach my $chr (keys %corf) {
  print $corf_outfile join("\n", keys %{$corf{$chr}}), "\n";
}
close $corf_outfile;

foreach my $chr (keys %GD_to_delete) {
  print $gd_outfile join("\n", keys %{$GD_to_delete{$chr}}), "\n";
}
close $gd_outfile;

################
# delete genes #
################

my $corf_genes = $support->param('corf_delete');
my $gd_genes   = $support->param('gd_delete');

if ($delete_corf_genes) {
  $support->param('delete',$corf_genes);
  my $options = $support->create_commandline_options({
    'allowed_params' => 1,
    'exclude' => [
      'prune',
      'logic_name',
      'corf_delete',
      'gd_delete'
    ],
    'replace' => {
      'interactive' => 0,
      'logfile'     => 'cleanup_corf_genes_delete_by_stable_id.log',
    }
  });
  $support->log("\nDeleting unwanted CORF genes from ".$support->param('dbname')."...\n");
  system("./delete_by_stable_id.pl $options") == 0
    or $support->throw("Error running delete_by_stable_id: $!");
}

if ($delete_gd_genes) {
  $support->param('delete',$gd_genes);
  my $options = $support->create_commandline_options({
    'allowed_params' => 1,
    'exclude' => [
      'prune',
      'logic_name',
      'corf_delete',
      'gd_delete'
    ],
    'replace' => {
      'interactive' => 0,
      'logfile'     => 'cleanup_GD_genes_delete_by_stable_id.log',
    }
  }); 
  $support->log("\nDeleting unwanted GD genes from ".$support->param('dbname')."...\n");
  system("./delete_by_stable_id.pl $options") == 0
    or $support->throw("Error running delete_by_stable_id: $!");
}

$support->finish_log;

exit;
