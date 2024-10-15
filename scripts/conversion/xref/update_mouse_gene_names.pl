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

update_mouse_gene_names.pl

=head1 SYNOPSIS

update_mouse_gene_names.pl [options]

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

    -mgi_file=FILE                      read MGI description from file

=head1 DESCRIPTION

Update name, description and status of protein coding genes that have a 'real' symbol
at MGI but an old name in Vega.

The background to this is that the gene names in Vega are often out of date compared to
those held at MGI. This script updates the display_xrefs (ie names) and descriptions of
protein coding Vega genes that fall into this class, and if the gene.status is NOVEL it
patches it KNOWN.

The way it does this is to use existing MarkerSymbol xrefs as display xrefs - these are
added by add_external_xrefs.pl using both mgivega and mgi as the xrefformat so this script
must be run after both of these have.

A complication is that some of the names that are assigned to Vega genes by MGI are not
of the right type to be used by Havana. So for example obvious cDNA names, NCBI gene models
are not used and are easily ignored by pattern matching. Unfortunately though there are some
names that can't be ignored based on the structure of their name - the decision on whether
to use them or not is made by jel. New names reported by the script are fed back to jel and
than added to either of the lists in this script.

After running it rerun add_external_xrefs.pl with mgi xrefformat to add external xrefs to
the genes that have been patched.

To Do:

- check alt_allele table for patched genes and patch these as well
- add synonyms for old gene name ?


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

#non-standard gene names jel says to not use
my @ignore_list = qw(D1Ertd622e D1Ertd471e D1Pas1 D2Bwg1335e D2Ertd391e U46068 N28178 D4Wsu132e D4Bwg0951e C87499 C77080 D4Ertd196e C79267 D4Ertd22e C87977 D4Wsu114e D6Mm5e D8Ertd457e C86695 P140 X83328 D11Wsu99e D11Wsu47e D11Bwg0517e C79407 D12Ertd647e D16Ertd472e D17Wsu92e C77370);

#non-standard gene names jel says we can use
my @use_list = qw(B3gat2 C4bp B3galt2 C8g S100a7a C1qc C1qdc2 C1qtnf P2rx7 B3gnt4 B3galtl C1galt1 H1fx B4galnt3 M6pr E2f8 p P4ha3 B3gat1 C1qtnf5 H2afv C1d B3gnt2 C1qtnf2 G3bp1 B9d1 B4galnt2 B3gntl1 B4galt7 C1qtnf9 R3hcc1 C9 C1qtnf3 B3gnt5 B4galt4 N6amt1 T L3mbtl4 F9 P2ry10),

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);
$support->parse_common_options(@_);
$support->parse_extra_options(
  'mgifile=s',
  'prune');
$support->allowed_params(
  $support->get_common_params,
  'mgifile',
  'prune');
$support->check_required_params('mgifile');	
if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}
$support->confirm_params;
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $sa = $dba->get_SliceAdaptor;
my $ga = $dba->get_GeneAdaptor;

#get description info from MGI file
my $descriptions = {};
&parse_mgi_for_desc( $descriptions );

#get chr details
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);

#create backup first time around
my %tables;
map { $_ =~ s/`//g; $tables{$_} += 1; } $dbh->tables;
if (! exists($tables{'backup_umgn_gene'}) ) {
	$dbh->do(qq(CREATE table backup_umgn_gene select * from gene));
}

#prune
if ($support->param('prune') and $support->user_proceed('Would you really like to delete changes from previous runs of this script ?')) {
	$dbh->do(qq(DELETE FROM gene));
	$dbh->do(qq(INSERT INTO gene SELECT * FROM backup_umgn_gene));
}

#need to identify MGI symbols that are attached to more than one stable ID - having
#duplicated gene names in Vega is not that bad, but is not at all good for loutre (to
#which this script will be ported
$support->log("Looping over chromosomes to find duplicated MGI symbols:\n\n");
my %all_MGI_names;
foreach my $chr (@chr_sorted) {
	#don't worry about duplications on IDD regions since there won't be any stable IDs
	#from there in the MGI file
	next if ($chr =~ /IDD/);
    my $slice = $sa->fetch_by_region('toplevel', $chr);
    my $genes = $slice->get_all_Genes('otter'); #ignore EUCOMM genes
 GENE:
    foreach my $gene (@{$genes}) {
		my $gsi = $gene->stable_id;;
        my $display_id;
		eval { $display_id = $gene->display_xref->display_id};
		if ($@) {
			$support->log_warning ("Can't get xref for gene $gsi on chr $chr, skipping\n");
			next GENE;
		}

		#get MGI name for this gene (set previously by add_external_xrefs.pl)
		foreach my $xref (@{$gene->get_all_DBEntries}) {
			if ($xref->dbname eq 'MarkerSymbol') {
				push @{$all_MGI_names{$xref->display_id}}, "$gsi ($display_id)";
			}
		}
	}
}
my %MGI_names_to_ignore;
my %stable_ids_to_ignore;
foreach my $MGI_name (keys %all_MGI_names) {
	if (scalar(@{$all_MGI_names{$MGI_name}}) > 1) {
		$MGI_names_to_ignore{$MGI_name} = 1;

		#report on the duplicated names, however this cannot
		#go to Havana / MGI for fixing since it's complicated by us using
		#synonyms
		foreach my $id (@{$all_MGI_names{$MGI_name}}) {
			$id =~ s/ \(.*//;
			$stable_ids_to_ignore{$id} = 1;
		}
		my $ids = join ',',@{$all_MGI_names{$MGI_name}};
		$support->log_verbose("MGI symbol $MGI_name matches multiple Vega genes $ids\n");
	}
}

#now go ahead and do the updates
$support->log("Looping over chromosomes to change Vega names: @chr_sorted\n\n");
my %name_changes;
foreach my $chr (@chr_sorted) {
    $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n");

    # fetch genes from db
	my $slice = $sa->fetch_by_region('toplevel', $chr);
    my $genes = $slice->get_all_Genes('otter'); #ignore EUCOMM genes
	$support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");
 GENE:
    foreach my $gene (@{$genes}) {
        my $display_id;
		my $gsi = $gene->stable_id;;

		eval { $display_id = $gene->display_xref->display_id};
		if ($@) {
			$support->log_warning ("Can't get xref for gene $gsi on chr $chr, skipping\n");
			next GENE;
		}
		my $disp_xref_dbname = $gene->display_xref->dbname;

		#ignore genes that already have a MarkerSymbol display_xref
		next GENE if ( $disp_xref_dbname eq 'MarkerSymbol');
		
		#ignore non-coding genes
		next GENE if ($gene->biotype ne 'protein_coding');
		
		#ignore if the MGI name attached to this is duplicated
		if ($stable_ids_to_ignore{$gsi}) {
			$support->log("Skipping gene $gsi because its MGI name has duplicate Vega stable IDs in this database\n");
			next GENE;
		}
		
		$support->log("Looking at gene $gsi - $display_id (source = $disp_xref_dbname):\n");

		#get MGI xref for this gene (set previously using MGIVega.rpt file)
		my $MGI_xref = '';
		foreach my $xref (@{$gene->get_all_DBEntries}) {
			if ($xref->dbname eq 'MarkerSymbol') {
				if ($MGI_xref) {
					$support->log_warning("$gsi has more than one MarkerSymbol xref! Skipping\n",1);
					next GENE;
				}
				else {
					$MGI_xref = $xref;
				}
			}
		}

		next GENE if (! $MGI_xref);

		#skip MGI names that are not real names:
        # (i) clone based names have two capital letters
		# (ii) names that are Gene models (Gm)
		# (iii) names that end in Rik are Riken cDNA names
		if ( ($MGI_xref->display_id =~ /[A-Z]{2}|Gm/) || ($MGI_xref->display_id =~ /Rik$/) ) {
			$support->log_verbose("$gsi - ignoring MGI name ".$MGI_xref->display_id." because of format\n",1);
			next GENE;
		}

		#skip non-standard MGI names that we know to ignore
		if ( grep { $MGI_xref->display_id eq $_ } @ignore_list) {
			$support->log_verbose("$gsi - ignoring MGI name ".$MGI_xref->display_id." since jel says to!\n",1);
			next GENE;
		}
		#report non-standard names that are new
		unless (grep { $MGI_xref->display_id eq $_ } @use_list) {
			$support->log_warning("$gsi - I don't know what to do with MGI name ".$MGI_xref->display_id."\n",1);
			next GENE;
		}
			
		#update display_xref;
		$gene->display_xref($MGI_xref);
		$support->log("$gsi - display_xref $display_id should be updated to MarkerSymbol ".$MGI_xref->display_id."\n",1);				
		$name_changes{$gsi} = "$display_id ==> ".$MGI_xref->display_id;

		#update description
		if (my $new_description = $descriptions->{$MGI_xref->primary_id}) {
			if ($new_description ne $gene->description) {
				$gene->description($new_description);
				$support->log("Description updated to \'$new_description\'\n",1);
			}
			else {
				$support->log_verbose("Description not needed to be updated\n",1);
			}
		}
		else {
			$support->log_warning("Cannot get description for ".$MGI_xref->primary_id." from parsed file\n",1);
		}

		#update status if necc
		if ($gene->status ne 'KNOWN') {
			$support->log("Status should be updated to KNOWN\n",1);
			$gene->status('KNOWN');				
		}			
		if ($MGI_xref->display_id eq $display_id) {
			$support->log_warning("Why has $gsi not got a MarkerSymbol display_xref already ?\n");
		}

		if (! $support->param('dry_run')) {
			$ga->update($gene);
		}
	}
}

$support->log("Summary:\n-------\n");
my $c = 0;
foreach my $gsi (sort keys %name_changes) {
	$c++;
	$support->log("$c. $gsi: $name_changes{$gsi}\n");
}

my $ids = '(';
foreach my $gsi (sort keys %name_changes) {
	$ids .= "'$gsi',";
}
$ids .= ')';
$support->log("$ids\n");

$support->finish_log;


=head2 parse_mgi_for_desc

  Arg[1]      : hashref
  Example     : &parse_mgi($desc);
  Description : parse mgi file for MarkerSymbols and associated descriptions
  Return type : none
  Exceptions  : thrown if input file can't be read
  Caller      : internal

=cut

sub parse_mgi_for_desc {
   my ($desc) = @_;
   $support->log_stamped("Parsing MGI for descriptions...\n", 1);

   # read input file
   my $mgifile = $support->param('mgifile');
   open(MGI, "< $mgifile")
	   or $support->throw("Couldn't open $mgifile for reading: $!\n");

   #parse input file
   while (<MGI>) {
	   my @fields = split /\t/;
	   #add mgi entries
	   my $mgi_pid = $fields[0];
	   my $mgi_desc = $fields[2];
	   if (exists($desc->{$mgi_pid})) {
		   $support->log_warning("Multiple descriptions parsed for $mgi_pid\n");
	   }
	   $desc->{$mgi_pid} = $mgi_desc;
   }
}


