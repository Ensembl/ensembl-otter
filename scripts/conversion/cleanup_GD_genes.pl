#!/usr/local/bin/perl

#!/usr/local/bin/perl

=head1 NAME

set_corf_genes.pl - set analysis_id for CORF genes and transcripts

=head1 SYNOPSIS

set_corf_genes.pl [options]

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

    --logic_name=NAME                   logicname for CORF genes (defaults to otter_corf)
    --chromosomes=LIST                  List of chromosomes to read (not working)

=head1 DESCRIPTION

This script identifies all CORF genes in a Vega database and sets the analysis_id for each.
It also sets the analysis_id of the transcripts.

Logic is:
(i) retrieve each gene with a GD: prefix on it's name (gene display_xref)
(ii) if that gene has at least one transcript with a remark of either 'Annotation_remark- corf',
or one that starts with the term 'corf', then set the analysis_id to otter_corf


Reports on other GD: loci that have other remarks containing 'corf'.
Verbosely reports on non GD: loci that have remarks containing 'corf'.

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
    'logic_name=s',
    'chromosomes|chr=s@',
);
$support->allowed_params(
    $support->get_common_params,
    'logic_name',
    'chromosomes',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}


$support->comma_to_list('chromosomes');

$support->param('logic_name','otter_corf') unless $support->param('logic_name');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;
my $ga  = $dba->get_GeneAdaptor;
my $sa  = $dba->get_SliceAdaptor;
my $ta  = $dba->get_TranscriptAdaptor;
my $aa = $dba->get_AttributeAdaptor;

# make a backup tables the first time the script is run
my @tables = qw(gene transcript);
my %tabs;
map { $_ =~ s/`//g; $tabs{$_} += 1; } $dbh->tables;
foreach my $table (@tables) {
	my $t = 'backup_scg_'.$table;
	if (! exists ($tabs{$t})) {
		$support->log("Creating backup ($t) of $table\n\n");
		$dbh->do(qq(CREATE table $t SELECT * FROM $table));
	}
}


#undo previous if needed
if ($support->param('prune')
	  && $support->user_proceed("\nDo you want to undo changes from previous runs of this script?")) {
	foreach my $table (@tables) {
		my $t = 'backup_ftn_'.$table;
		$dbh->do(qq(DELETE FROM $table));
		$dbh->do(qq(INSERT INTO $table SELECT * FROM $t));
	}
}


my $patch_trans = 0;
if ($support->user_proceed("\nSet analysis_ids to of CORF transcripts equal those of their genes ?")) {	
	$patch_trans = 1;
}


my (%non_GD,%to_change,%wrong_syntax_GD,%wrong_syntax_nonGD);

my @chroms;
foreach my $chr ($support->sort_chromosomes) {
	push @chroms,  $sa->fetch_by_region('toplevel', $chr);
}

foreach my $slice (@chroms) {
	$support->log_stamped("Looping over chromosome ".$slice->seq_region_name."\n");
    my $genes = $slice->get_all_Genes;
    $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");

    foreach my $gene (@$genes) {
		my $gsi = $gene->stable_id;
		my $name = $gene->display_xref->display_id;
		$support->log_verbose("Studying gene $gsi ($name)\n");
		my $found_remark = 0;

		#get all remarks
		my %remarks;
		foreach my $trans (@{$gene->get_all_Transcripts()}) {
			my $tsi = $trans->stable_id;
			foreach my $remark ( @{$trans->get_all_Attributes('remark')} ) {
				my $value = $remark->value;
				push @{$remarks{$tsi}},$value
			}
		}
		
		#look for correctly formatted remarks				
		foreach my $tsi (keys %remarks) {
			foreach my $value (@{$remarks{$tsi}} ) {
				if ( $value =~ /^Annotation_remark- corf/i) {
					$found_remark = 1;
					#capture nonGD genes with the correct remark
					if ($name !~ /^GD:/) {
						$non_GD{$gsi}->{'name'} = $name;
						push @{$non_GD{$gsi}->{'transcripts'}},$tsi;
					}
					#capture genes to patch analysis_id
					else {							
						$to_change{$gsi}->{'name'} = $name;
						push @{$to_change{$gsi}->{'transcripts'}}, [$tsi,$value];
					}
				}
			}
		}

		#other wise look for other 'corf' type remarks
		if (! $found_remark) { 
			foreach my $tsi (keys %remarks) {
				foreach my $value (@{$remarks{$tsi}} ) {
					if ($value =~ /corf/i) {
						#capture genes with a remark that should be a corf annotation remark
						if ( ($value =~ /^corf/i) && ($name =~ /^GD:/)) { 
							$support->log_warning("Setting gene $gsi to corf despite not having the properly formatted Annotation remark\n");
							$to_change{$gsi}->{'name'} = $name;
							push @{$to_change{$gsi}->{'transcripts'}}, [$tsi,$value];
						}
						#capture incorrect syntax
						else {
							if ($name =~ /^GD:/) {
								$wrong_syntax_GD{$gsi}->{'name'} = $name;
								push @{$wrong_syntax_GD{$gsi}->{'transcripts'}}, [$tsi,$value];
							}
							else {
								$wrong_syntax_nonGD{$gsi}->{'name'} = $name;
								push @{$wrong_syntax_nonGD{$gsi}->{'transcripts'}}, [$tsi,$value];
							}
						}
					}
				}									
			}
		}
	}
}

#report on GD genes with the incorrect syntax
$support->log("\nThe following are GD genes with the incorrect remark syntax:\n"); 
foreach my $gsi (keys %wrong_syntax_GD) {
	$support->log("\n$gsi (".$wrong_syntax_GD{$gsi}->{'name'}."):\n",1);
	foreach my $t (@{$wrong_syntax_GD{$gsi}->{'transcripts'}}) {
		$support->log($t->[0]." (".$t->[1].")\n",2);
	}
}

#report on non GD genes with the incorrect syntax
$support->log_verbose("\nThe following are non GD genes with the incorrect remark CORF syntax:\n"); 
foreach my $gsi (keys %wrong_syntax_nonGD) {
	$support->log_verbose("\n$gsi (".$wrong_syntax_nonGD{$gsi}->{'name'}."):\n",1);
	foreach my $t (@{$wrong_syntax_nonGD{$gsi}->{'transcripts'}}) {
		$support->log_verbose($t->[0]." (".$t->[1].")\n",2);
	}
}

#report on non GD genes with the correct syntax
$support->log_verbose("\nThe following are non GD genes with the correct CORF remark syntax:\n");
my $c = 0;
foreach my $gsi (keys %non_GD) {
	$c++;
	$support->log_verbose("\n$gsi (".$non_GD{$gsi}->{'name'}."):\n",1);
	foreach my $t (@{$non_GD{$gsi}->{'transcripts'}}) {
		$support->log_verbose($t."\n",2);
	}
}
$support->log("\n$c non GD genes with the correct CORF syntax in total.\n\n");

#report on GD genes with the correct syntax, ie the ones to be updated
$support->log("\nThe following GD genes with the correct CORF remark syntax will be updated:\n");
$c = 0;
my @gene_stable_ids;
foreach my $gsi (keys %to_change) {
	$c++;
	push @gene_stable_ids, $gsi;
	$support->log("\n$gsi (".$to_change{$gsi}->{'name'}."):\n",1);
	foreach my $t (@{$to_change{$gsi}->{'transcripts'}}) {
		$support->log_verbose($t->[0]." (".$t->[1].")\n",2);
	}
}
$support->log("\n$c GD genes with the correct CORF syntax in total.\n\n");

#do the updates
# add analysis
if (! $support->param('dry_run')) {
    $support->log("Adding new analysis...\n");
    my $analysis = new Bio::EnsEMBL::Analysis (
        -program     => "set_corf_genes.pl",
        -logic_name  => $support->param('logic_name'),
    );
    my $analysis_id = $dba->get_AnalysisAdaptor->store($analysis);
    $support->log_error("Couldn't store analysis ".$support->param('analysis').".\n") unless $analysis_id;

    # change analysis for genes in list
    $support->log("Updating analysis of genes in list...\n");
    my $gsi_string = join("', '", @gene_stable_ids);
    my $num = $dbh->do(qq(
        UPDATE gene g, gene_stable_id gsi
           SET analysis_id = $analysis_id
         WHERE g.gene_id = gsi.gene_id
           AND gsi.stable_id in ('$gsi_string')
    ));
    $support->log("Done updating $num genes.\n\n");

	#change analysis_ids of transcripts
	if ($patch_trans) {
		$support->log("Updating analysis of corresponding transcripts...\n");
		$dbh->do(qq(
            UPDATE transcript t, gene g, gene_stable_id gsi
               SET t.analysis_id = g.analysis_id
             WHERE t.gene_id = g.gene_id
               AND g.gene_id = gsi.gene_id
               AND gsi.stable_id in ('$gsi_string')
        ));
		$support->log("Done updating transcripts.\n\n");
	}
	else {
		$support->log("Transcripts analysis_ids not updated.\n\n");
	}
}

$support->finish_log;
