#!/usr/local/bin/perl

=head1 NAME

accession_to_support.pl - script to add supporting evidence to a Vega database

=head1 SYNOPSIS

accession_to_support.pl [options]

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

This script adds the supporting evidence for Vega. It does so by comparing
accessions between annotated evidence and similarity features from the protein
and dna align feature tables. If a match is found, it is added to the supporting_feature
and transcript_supporting_feature tables.

Pseudocode:

    foreach gene
        get all similarity features, store in datastructure
        foreach transcript
            get all annotated evidence
            foreach evidence
                foreach similarity feature
                    accession matches?
                        foreach exon
                            similarity feature overlaps exon?
                                store supporting evidence

There are occasions where no match for annotated evidence can be found.
Possible reasons for this are: spelling mistake by annotator; feature not found
by protein pipeline run (e.g. removed from external database, renamed)

There si no prune option - changes can be easily undone by deleting entries from
transcript_supporting_feature and supporting_feature

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>
Patrick Meidl <meidl@ebi.ac.uk>


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

# statement handles for storing supporting evidence
my $sth = $dba->dbc->prepare(qq(
    INSERT INTO supporting_feature
        (exon_id, feature_id, feature_type)
    VALUES(?, ?, ?)
));
my $sth1 = $dba->dbc->prepare(qq(
    INSERT INTO transcript_supporting_feature
        (transcript_id, feature_id, feature_type)
    VALUES(?, ?, ?)
));

my @gene_stable_ids = $support->param('gene_stable_id');
my %gene_stable_ids = map { $_, 1 } @gene_stable_ids;
my $chr_length = $support->get_chrlength($dba);
my @chr_sorted = $support->sort_chromosomes($chr_length);
my %analysis = map { $_->logic_name => $_ } @{ $aa->fetch_all };
my %ftype = (
    'Bio::EnsEMBL::DnaDnaAlignFeature' => 'dna_align_feature',
    'Bio::EnsEMBL::DnaPepAlignFeature' => 'protein_align_feature',
);

#set up data structures to store details of which evidence table entries are in the align_feature tables
my %evidence_stats = map {$_ => 0 } qw(evidence_with_match evidence_without_match evidence_without_covered_match);
my $all_alignments = {};
my $all_evidence = {};

# loop over chromosomes
$support->log("Looping over chromosomes: @chr_sorted\n\n");
foreach my $chr (@chr_sorted) {
    $support->log_stamped("> Chromosome $chr (".$chr_length->{$chr}."bp).\n\n");

#	next;

    # fetch genes from db
    $support->log("Fetching genes...\n");
    my $slice = $sa->fetch_by_region('toplevel', $chr);
    my $genes = $slice->get_all_Genes;
    $support->log_stamped("Done fetching ".scalar @$genes." genes.\n\n");

    # loop over genes
    my %stats = map { $_ => 0 } qw(genes transcripts exons genes_without_support transcripts_without_support);
    my @transcripts_without_support;
    foreach my $gene (@$genes) {
        my $gsi = $gene->stable_id;
        my $gid = $gene->dbID;
        my $gene_name = $gene->display_xref->display_id;

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
        
        $stats{'genes'}++;
        my %se_hash = ();
        my %tse_hash = ();
        my $gene_has_support = 0;
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
            $stats{'transcripts'}++;
            $support->log_verbose("Transcript ".$trans->stable_id."...\n", 1);

            # loop over evidence added by annotators for this transcript
            my @evidence = @{$trans->evidence_list};
#			warn Dumper(\@evidence);
#			exit;

            my @exons = @{ $trans->get_all_Exons };
            $stats{'exons'} += scalar(@exons);
            foreach my $evi (@evidence) {
                my $acc = $evi->name;
                $acc =~ s/.*://;
                $acc =~ s/\.[0-9]*$//;
				my $acc_type = $evi->type;
				$all_evidence->{$acc_type}{$acc}++;
                my $ana = $analysis{$evi->type . "_evidence"};
                $support->log_verbose("Evidence $acc...\n", 2);
                # loop over similarity features on the slice, compare name with
                # evidence
                my $match = 0;
                foreach my $hitname (keys %$sf) {
                    if ($hitname eq $acc) {
                        foreach my $hit (@{ $sf->{$hitname} }) {
                            # store transcript supporting evidence
                            if ($trans->end >= $hit->[0] && $trans->start <= $hit->[1]) {
                                # store unique evidence identifier in hash
                                $tse_hash{$trans->dbID.":".$hit->[2].":".$hit->[3]} = 1;

                                $match = 1;
                                $gene_has_support++;
                                $transcript_has_support++;
                            }

                            # loop over exons and look for overlapping
                            # similarity features
                            foreach my $exon (@exons) {
                                if ($exon->end >= $hit->[0] && $exon->start <= $hit->[1]) {
                                    $support->log_verbose("Matches similarity feature with dbID ".$hit->[2].".\n", 3);
                                    # store unique evidence identifier in hash
                                    $se_hash{$exon->dbID.":".$hit->[2].":".$hit->[3]} = 1;
                                }
                            }
                        }
                    }
					else {
						$stats{'evidence_without_match'}{$acc}++;
					}
                }
				if (!$match) {
					$support->log_verbose("No matching similarity feature found for $acc.\n", 3);
					$stats{'evidence_without_covered_match'}{$acc}++;
				}
            }
            unless ($transcript_has_support) {
                $stats{'transcripts_without_support'}++;
                push @transcripts_without_support, $trans->stable_id." on gene ".$gsi;
            }
        }
        $stats{'genes_without_support'}++ unless ($gene_has_support);

        $support->log_verbose("Found $gene_has_support matches (".
                       scalar(keys %se_hash)." unique).\n", 1);

        # store supporting evidence in db
        unless ($support->param('dry_run')) {
            foreach my $tse (keys %tse_hash) {
                eval {
                    $sth1->execute(split(":", $tse));
                };
                $support->log_warning("$gsi: $@\n", 1) if ($@);
            }
        }

        if ($gene_has_support and !$support->param('dry_run')) {
            $support->log_verbose("Storing supporting evidence... ".
                           $support->date_and_mem."\n", 1);
            foreach my $se (keys %se_hash) {
                eval {
                    $sth->execute(split(":", $se));
                };
                if ($@) {
                    $support->log_warning("$gsi: $@\n", 1);
                }
            }
            $support->log_verbose("Done storing evidence. ".
                           $support->date_and_mem."\n", 1);
        }
    }
    $support->log("\nProcessed $stats{genes} genes (of ".scalar @$genes." on chromosome $chr), $stats{transcripts} transcripts, $stats{exons} exons.\n");
    $support->log("WARNINGS:\n");
    if ($stats{'genes_without_support'}) {
        $support->log("No supporting evidence for any transcripts on $stats{genes_without_support} genes.\n", 1);
        $support->log("No supporting evidence for $stats{transcripts_without_support} transcripts.\n", 1);
        $support->log("Transcripts without supporting evidence:\n", 1);
        foreach (@transcripts_without_support) {
            $support->log("$_\n", 2);
        }
    } else {
        $support->log("None.\n");
    }
    $support->log("Done with chromosome $chr. ".$support->date_and_mem."\n\n");
}

#look at overall stats for evidence table
#$all_evidence->{'cDNA'}{'AW868554'} = 1;
#$all_evidence->{'protein'}{'P13584'} = 1;

if ($support->param('check_evidence_table')) {
	$support->log("Examining links between evidence table and align_feature tables\n");
	foreach my $t ('dna_align_feature','protein_align_feature') {
		$support->log_stamped("Retrieving features from $t\n",1);
		my $sth = $dba->dbc->prepare(qq(Select hit_name from $t));
		$sth->execute;
		while (my ($name) = $sth->fetchrow_array) {
			$name =~ s/\.[0-9]*$//;
			$all_alignments->{$name}++;
		}
	}

	foreach my $type (keys %{$all_evidence}) {
		my ($match,$no_match) = (0,0);
		$support->log("Evidence type $type:\n");
		foreach my $acc (keys %{$all_evidence->{$type}}) {
			if (exists ($all_alignments->{$acc})) {
				$match++;
			}
			else {
				$no_match++;
			}
		}
		$support->log("$match accessions match to align_features; $no_match accessions do not match to align_features\n",1);
	}
}
		
# finish log
$support->finish_log;

