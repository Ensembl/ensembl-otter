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

check_evidence.pl - quick script to check supporting evidence in a Vega database

=head1 SYNOPSIS

check_evidence.pl [options]

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

    --chromosomes, --chr=LIST           only process LIST chromosomes
    --gene_stable_id, --gsi=LIST|FILE   only process LIST gene_stable_ids
                                        (or read list from FILE)
    --check_evidence_table              examine links between evidence and align_feature tables
                                        (for data curation)

=head1 DESCRIPTION

Create tables containing IDs of genes / transcripts / exons that either don't have evidence,
or supporting features.


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
    unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
    'chromosomes|chr=s@',
    'gene_stable_id|gsi=s@',
	'check_evidence_table=s',
);
$support->allowed_params(
    $support->get_common_params,
    'chromosomes',
    'gene_stable_id',
	'check_evidence_table',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('chromosomes');
$support->list_or_file('gene_stable_id');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors (caching features on one slice only)
my $dba = $support->get_database('loutre');
my $sa = $dba->get_SliceAdaptor();
my $ga = $dba->get_GeneAdaptor();
my $aa = $dba->get_AnalysisAdaptor();

#create MySQL tables and statement handles to hold results
my %sths;

foreach my $t (qw(genes_without_evidence
				  genes_without_support
				  )) {
	$dba->dbc->do(qq(DROP TABLE IF EXISTS `$t`));
	my $sql = qq(Create table `$t` (
                                    `gene_id` int(10) unsigned NOT NULL,
                                    PRIMARY KEY  (`gene_id`)
                                    ) ENGINE=MyISAM DEFAULT CHARSET=latin1);
	$dba->dbc->do($sql);
	$sths{$t} = $dba->dbc->prepare(qq(INSERT INTO $t values (?)));
}
foreach my $t (qw(transcripts_without_evidence
				  transcripts_without_support
				  )) {
	$dba->dbc->do(qq(DROP TABLE IF EXISTS `$t`));
	my $sql = qq(Create table `$t` (
                                    `transcript_id` int(10) unsigned NOT NULL,
                                    PRIMARY KEY  (`transcript_id`)
                                    ) ENGINE=MyISAM DEFAULT CHARSET=latin1);
	$dba->dbc->do($sql);
	$sths{$t} = $dba->dbc->prepare(qq(INSERT INTO $t values (?)));
}
foreach my $t (qw(exons_without_support)) {
	$dba->dbc->do(qq(DROP TABLE IF EXISTS `$t`));
	my $sql = qq(Create table `$t` (
                                    `exon_id` int(10) unsigned NOT NULL,
                                    `transcript_id` int(10) unsigned NOT NULL,
                                    UNIQUE KEY `transcript_index` (`exon_id`,`transcript_id`)
                                    ) ENGINE=MyISAM DEFAULT CHARSET=latin1);
	$dba->dbc->do($sql);
	$sths{$t} = $dba->dbc->prepare(qq(INSERT INTO $t values (?,?)));
}

my @gene_stable_ids = $support->param('gene_stable_id');
my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);
my %ftype = (
    'Bio::EnsEMBL::DnaDnaAlignFeature' => 'dna_align_feature',
    'Bio::EnsEMBL::DnaPepAlignFeature' => 'protein_align_feature',
);
# loop over chromosomes
$support->log("Looping over chromosomes: @chr_sorted\n\n");
foreach my $chr (@chr_sorted) {
    $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");

    # fetch genes from db
    $support->log("Fetching genes...\n");
    my $slice = $sa->fetch_by_region('toplevel', $chr);
    my $genes = $slice->get_all_Genes;
    $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");

    # loop over genes
    foreach my $gene (@$genes) {
        my $gsi = $gene->stable_id;
        my $gid = $gene->dbID;

		#use original loutre name attributes since likely to be reporting back to Havana
        my $gene_name = $gene->get_all_Attributes('name')->[0]->value;
		my $source = $gene->source;

		#skip KO genes since they shouldn't have supporting evidence
		next if ($gene->analysis->logic_name eq 'otter_eucomm');

        # filter to user-specified gene_stable_ids
        if (scalar(@gene_stable_ids)){
            next unless $gene_stable_ids{$gsi};
        }

        # adjust gene's slice to cover gene +/- 1000 bp
        my $gene_slice = $sa->fetch_by_region('toplevel', $chr, $gene->start - 1000, $gene->end + 1000);
        $gene = $gene->transfer($gene_slice);
        unless ($gene) {
            $support->log_warning("Gene $gene_name ($gid, $gsi) doesn't transfer to padded gene_slice.\n");
            next;
        }
        my $gene_has_support = 0;
        my $gene_has_evidence = 0;
        $support->log_verbose("Gene $gene_name ($gid, $gsi) on slice ".$gene->slice->name."...\n");

        # fetch similarity features from db and store required information in
        # lightweight datastructure (name => [ start, end, dbID, type ])
        $support->log_verbose("Fetching similarity features...\n",1);
        my $similarity = $gene_slice->get_all_SimilarityFeatures;
        my $sf = {};
        foreach my $f (@$similarity) {
            (my $hitname = $f->hseqname) =~ s/\.[0-9]*$//;
            push @{ $sf->{$hitname} },
                 [ $f->start, $f->end, $f->dbID, $ftype{ref($f)} ];
        }
        $support->log_verbose("Done fetching ".(scalar @$similarity)." features\n", 1);

        # loop over transcripts
        foreach my $trans (@{ $gene->get_all_Transcripts }) {
            my $transcript_has_support = 0;
            my $transcript_has_evidence = 0;
			my $tsid = $trans->stable_id;
            $support->log_verbose("Transcript $tsid...\n", 1);
            # loop over evidence added by annotators for this transcript
            my @evidence = @{$trans->evidence_list};
            my @exons = @{ $trans->get_all_Exons };
			my %exons_with_support = map {$_->dbID => 0} @exons;
#			warn Dumper(\%exons_with_support);
#			exit;
            foreach my $evi (@evidence) {
				$transcript_has_evidence = 1;
				$gene_has_evidence = 1;
                my $acc = $evi->name;
                $acc =~ s/.*://;
				$acc =~ s/\.[0-9]*$//;
                $support->log_verbose("Evidence $acc...\n", 2);
                # loop over similarity features on the slice, compare name with evidence
                foreach my $hitname (keys %$sf) {
                    if ($hitname eq $acc) {
                        foreach my $hit (@{ $sf->{$hitname} }) {
                            # store transcript supporting evidence
                            if ($trans->end >= $hit->[0] && $trans->start <= $hit->[1]) {
                                $gene_has_support = 1;
                                $transcript_has_support = 1;
                            }

                            # loop over exons and look for overlapping similarity features
                            foreach my $exon (@exons) {
                                if ($exon->end >= $hit->[0] && $exon->start <= $hit->[1]) {
									$exons_with_support{$exon->dbID} = 1;
									$support->log_verbose("Matches similarity feature with dbID ".$hit->[2].".\n", 3);
                                }
							}
						}
					}
				}
			}
			foreach my $exon_id (keys %exons_with_support) {
				if (! $exons_with_support{$exon_id}) {
					eval { $sths{'exons_without_support'}->execute($exon_id,$trans->dbID);};
					if ($@) {
						$support->log_warning("Something's wrong here $@\n");
					}
				}
			}

			if ( ! $transcript_has_support ) {
				$sths{'transcripts_without_support'}->execute($trans->dbID);
			}
			if ( ! $transcript_has_evidence ) {
				$sths{'transcripts_without_evidence'}->execute($trans->dbID);
			}
		}
		if ( ! $gene_has_support ) {
			$sths{'genes_without_support'}->execute($gene->dbID);
			}
		if ( ! $gene_has_evidence ) {
			$sths{'genes_without_evidence'}->execute($gene->dbID);
		}	
	}
	$support->log("Done with chromosome $chr. ".$support->date_and_mem."\n\n");
}

# finish log
$support->finish_log;

