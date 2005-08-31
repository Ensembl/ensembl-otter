#!/usr/local/bin/perl

=head1 NAME

align_by_clone_identity.pl - create a whole genome alignment between two closely
related assemblies, step 1

=head1 SYNOPSIS

align_by_clone_identity.pl [options]

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
    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host
                                        HOST
    --evegaport=PORT                    use ensembl-vega (target) database port
                                        PORT
    --evegauser=USER                    use ensembl-vega (target) database
                                        username USER
    --evegapass=PASS                    use ensembl-vega (target) database
                                        passwort PASS

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

This script creates a whole genome alignment between two closely related
assemblies (e.g. a Vega human assembly and the corresponding NCBI assembly used
in Ensembl). You will need a database containing both assemblies which can be
created with the script make_ensembl_vega_db.pl. The alignment is created in
two steps:

    1. Match clones with same name and version directly and create alignment
       blocks for these regions. Clones can be tagged manually to be excluded
       from these direct matches by adding a seq_region_attrib of type
       "skip_clone" to the Vega source database. This can be useful to get
       better results in regions with major assembly differences (eg human chr
       9).
       
       The result is stored in the assembly table as an assembly between the
       chromosomes of both genome assemblies.

    2. Store non-aligned blocks in a temporary table (tmp_align). They can
       later be aligned using blastz by align_nonident_regions.pl.

=head1 RELATED SCRIPTS

The whole Ensembl-vega database production process is done by these scripts:

    ensembl-otter/scripts/conversion/assembly/make_ensembl_vega_db.pl
    ensembl-otter/scripts/conversion/assembly/align_by_clone_identity.pl
    ensembl-otter/scripts/conversion/assembly/align_nonident_regions.pl
    ensembl-otter/scripts/conversion/assembly/map_annotation.pl
    ensembl-otter/scripts/conversion/assembly/finish_ensembl_vega_db.pl

See documention in the respective script for more information.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

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
    $SERVERROOT = "$Bin/../../../..";
    unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::EnsEMBL::Attribute;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
    'chromosomes|chr=s@',
    'evegahost=s',
    'evegaport=s',
    'evegauser=s',
    'evegapass=s',
    'evegadbname=s',
);
$support->allowed_params(
    $support->get_common_params,
    'chromosomes',
    'evegahost',
    'evegaport',
    'evegauser',
    'evegapass',
    'evegadbname',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('chromosomes');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# suggest to run non-verbosely
my $txt = qq(Running this script with the --verbose option will create a lot of output.
It is recommended to do this only for debug purposes.
Shall I switch to non-verbose logging for you?);

if ($support->param('verbose') and $support->user_proceed($txt)) {
    $support->param('verbose', 0);
}

# connect to database and get adaptors
my $V_dba = $support->get_database('core');
my $V_dbh = $V_dba->dbc->db_handle;
my $V_sa = $V_dba->get_SliceAdaptor;
my $E_dba = $support->get_database('evega', 'evega');
my $E_dbh = $E_dba->dbc->db_handle;
my $E_sa = $E_dba->get_SliceAdaptor;
my $E_aa = $E_dba->get_AttributeAdaptor;

# create attribute to indicate that a chromosome is identical to Ensembl
my $attrib = Bio::EnsEMBL::Attribute->new(
        -CODE           => 'ensembl_ident',
        -NAME           => 'Ensembl identity',
        -VALUE          => 1,
        -DESCRIPTION    => 'Flag indicating seq_region identity with Ensembl',
);

# create temporary table for storing non-aligned blocks
unless ($support->param('dry_run')) {
    $E_dbh->do(qq(
        CREATE TABLE IF NOT EXISTS tmp_align (
            tmp_align_id int(10) unsigned NOT NULL auto_increment,
            seq_region_name varchar(10) NOT NULL,
            e_start int(10) UNSIGNED NOT NULL,
            e_end int(10) UNSIGNED NOT NULL,
            v_start int(10) UNSIGNED NOT NULL,
            v_end int(10) UNSIGNED NOT NULL,
            
            PRIMARY KEY (tmp_align_id)
        )
    ));

    # clear tmp_align table of entries from previous runs
    $E_dbh->do(qq(DELETE FROM tmp_align));
}

# get Vega and Ensembl chromosomes
my $V_chrlength = $support->get_chrlength($E_dba, $support->param('assembly'));
my $E_chrlength = $support->get_chrlength($E_dba, $support->param('ensemblassembly'));

# loop over chromosomes
$support->log_stamped("Looping over chromosomes...\n");
my $match = {};
my $nomatch = {};
my %stats_total;
my @block_length;
my $fmt1 = "%-35s%10.0f\n";
my $fmt2 = "%-35s%9.2f%%\n";
my $fmt3 = "%-12s%-12s%-10s%-12s%-12s%-9s\n";
my $fmt4 = "%10.0f  %10.0f  %7.0f   %10.0f  %10.0f  %7.0f\n";
my $sth1 = $E_dbh->prepare(qq(
    INSERT INTO assembly (asm_seq_region_id, cmp_seq_region_id, asm_start,
        asm_end, cmp_start, cmp_end, ori)
    VALUES (?, ?, ?, ?, ?, ?, 1)
));
my $sth2 = $E_dbh->prepare(qq(INSERT INTO tmp_align values(NULL, ?, ?, ?, ?, ?)));
foreach my $chr ($support->sort_chromosomes($V_chrlength)) {
    $support->log_stamped("Chromosome $chr...\n", 1);
    
    # skip non-ensembl chromosomes (e.g. MHC haplotypes)
    unless ($E_chrlength->{$chr}) {
        $support->log("Chromosome not in Ensembl. Skipping.\n", 1);
        next;
    }

    # fetch chromosome slices
    my $V_slice = $V_sa->fetch_by_region('chromosome', $chr, undef, undef, undef, $support->param('assembly'));
    my $E_slice = $E_sa->fetch_by_region('chromosome', $chr, undef, undef, undef, $support->param('ensemblassembly'));

    # project to clones
    my @V_clones = @{ $V_slice->project('clone') };
    my @E_clones = @{ $E_slice->project('clone') };

    # loop over Ensembl clones
    my $last = 0;
    my $j = 0;
    my $match_flag = 0;
    my $last_E_seg;
    my %stats_chr;
    foreach my $E_seg (@E_clones) {  
        my $E_clone = $E_seg->to_Slice;
        $support->log_verbose("Ensembl clone ($j) ".$E_clone->seq_region_name.":".$E_clone->start."-".$E_clone->end.":".$E_clone->strand." $chr:".$E_seg->from_start."-".$E_seg->from_end."\n", 2);
        # walk Vega clones
        VEGACLONES:
        for (my $i = $last; $i < scalar(@V_clones); $i++) {
            my $V_clone = $V_clones[$i]->to_Slice;
            # same name.version and strand found
            if ($E_clone->seq_region_name eq $V_clone->seq_region_name and
                $E_clone->strand == $V_clone->strand) {

                # same clone start/end -> identical assembly
                if ($E_clone->start == $V_clone->start and $E_clone->end == $V_clone->end) {
                    # check if clone is tagged to be skipped
                    # this is to resolve some odd assembly differences,
                    # relevant clones will have to be tagged manually (for now;
                    # write script to do this from input list)
                    my ($skip) = @{ $V_clone->get_all_Attributes('skip_clone') };
                    if ($skip) {
                        $support->log_verbose("Skipping matching Vega clone ($i)".
                        $V_clone->seq_region_name.":".$V_clone->start."-".
                        $V_clone->end.":".$V_clone->strand."$chr:".
                        $V_clones[$i]->from_start."-".$V_clones[$i]->from_end.
                        "\n", 2);
                        
                        &found_nomatch($chr, $match, $nomatch, $E_seg,
                            $last_E_seg, $V_clones[$i], $V_clones[$i-1],
                            $match_flag, $i, $j
                        );

                        $stats_chr{'skipped'}++;
                        $match_flag = 0;
                    } else {
                        $support->log_verbose("Found matching Vega clone ($i)".
                        $V_clone->seq_region_name.":".$V_clone->start."-".
                        $V_clone->end.":".$V_clone->strand."$chr:".
                        $V_clones[$i]->from_start."-".$V_clones[$i]->from_end.
                        "\n", 2);

                        &found_match($chr, $match, $nomatch, $E_seg,
                            $last_E_seg, $V_clones[$i], $V_clones[$i-1],
                            $match_flag, $i, $j
                        );

                        $stats_chr{'identical'}++;
                        $match_flag = 1;
                    }

                # start/end mismatch
                } else {
                    $support->log_verbose("Start/end mismatch for clone ($i) ".$V_clone->seq_region_name.":".$V_clone->start."-".$V_clone->end.":".$V_clone->strand." $chr:".$V_clones[$i]->from_start."-".$V_clones[$i]->from_end."\n", 2);

                    &found_nomatch($chr, $match, $nomatch, $E_seg, $last_E_seg,
                        $V_clones[$i], $V_clones[$i-1], $match_flag, $i, $j
                    );

                    $stats_chr{'mismatch'}++;
                    $match_flag = 0;
                }
                $i++;
                $last = $i;
                last VEGACLONES;

            # different clones
            } else {
                $support->log_verbose("Skipping clone ($i)".$V_clone->seq_region_name.":".$V_clone->start."-".$V_clone->end.":".$V_clone->strand." $chr:".$V_clones[$i]->from_start."-".$V_clones[$i]->from_end."\n", 2);

                &found_nomatch($chr, $match, $nomatch, $E_seg, $last_E_seg, $V_clones[$i], $V_clones[$i-1], $match_flag, $i, $j);

                $match_flag = 0;
            }
        }
        
        $last_E_seg = $E_seg;
        $j++;
    }

    # adjust the final clone count
    if ($match_flag) {
        # last clone was a match, adjust matching clone count
        my $c = scalar(@{ $match->{$chr} || [] }) - 1;
        $match->{$chr}->[$c]->[2] = scalar(@E_clones) - $match->{$chr}->[$c]->[2];
        $match->{$chr}->[$c]->[5] = scalar(@V_clones) - $match->{$chr}->[$c]->[5];
    } else {
        # last clone was a non-match, adjust non-matching clone count
        my $c = scalar(@{ $nomatch->{$chr} || [] }) - 1;
        $nomatch->{$chr}->[$c]->[2] = scalar(@E_clones) - $nomatch->{$chr}->[$c]->[2];
        $nomatch->{$chr}->[$c]->[5] = scalar(@V_clones) - $nomatch->{$chr}->[$c]->[5];
    }

    # filter single assembly inserts from non-aligned blocks (i.e. cases where 
    # a block has clones only in one assembly, not in the other) - there is
    # nothing to be done with them
    @{ $nomatch->{$chr} } = grep { $_->[2] > 0 and $_->[5] > 0 } @{ $nomatch->{$chr} } if ($nomatch->{$chr});

    # store directly aligned blocks in assembly table
    unless ($support->param('dry_run')) {
        $support->log("Adding assembly entries for directly aligned blocks...\n", 1);
        my $c;
        for ($c = 0; $c < scalar(@{ $match->{$chr} || [] }); $c++) {
            $sth1->execute(
                $V_sa->get_seq_region_id($V_slice),
                $E_sa->get_seq_region_id($E_slice),
                $match->{$chr}->[$c]->[3],
                $match->{$chr}->[$c]->[4],
                $match->{$chr}->[$c]->[0],
                $match->{$chr}->[$c]->[1]
            );
        }
        $support->log("Done inserting $c entries.\n", 1);
    }

    # store non-aligned blocks in tmp_align table
    unless ($support->param('dry_run')) {
        if ($nomatch->{$chr}) {
            $support->log("Storing non-aligned blocks in tmp_align table...\n", 1);
            my $c;
            for ($c = 0; $c < scalar(@{ $nomatch->{$chr} }); $c++) {
                $sth2->execute(
                    $chr,
                    $nomatch->{$chr}->[$c]->[0],
                    $nomatch->{$chr}->[$c]->[1],
                    $nomatch->{$chr}->[$c]->[3],
                    $nomatch->{$chr}->[$c]->[4],
                );
            }
            $support->log("Done inserting $c entries.\n", 1);
        }
    }

    # flag chromosomes which are completely identical
    unless ($nomatch->{$chr}) {
        $support->log("Flagging chromosome as identical...\n", 1);
        $E_aa->store_on_Slice($E_slice, [$attrib]) unless ($support->param('dry_run'));
        $support->log("Done.\n", 1);
    }

    # stats for this chromosome
    $stats_chr{'E_only'} = scalar(@E_clones) - $stats_chr{'identical'} - $stats_chr{'mismatch'};
    $stats_chr{'V_only'} = scalar(@V_clones) - $stats_chr{'identical'} - $stats_chr{'mismatch'};
    for (my $c = 0; $c < scalar(@{ $match->{$chr} } || []); $c++) {
        $stats_chr{'E_matchlength'} += $match->{$chr}->[$c]->[1] - $match->{$chr}->[$c]->[0];
        $stats_chr{'V_matchlength'} += $match->{$chr}->[$c]->[4] - $match->{$chr}->[$c]->[3];
    }
    $stats_chr{'E_coverage'} = 100 * $stats_chr{'E_matchlength'} /  $E_slice->length;
    $stats_chr{'V_coverage'} = 100 * $stats_chr{'V_matchlength'} /  $E_slice->length;
    map { $stats_total{$_} += $stats_chr{$_} } keys %stats_chr;
    
    $support->log("\nStats for chromosome $chr:\n\n", 1);
    $support->log(sprintf($fmt1, "Length (Ensembl):", $E_slice->length), 2);
    $support->log(sprintf($fmt1, "Length (Vega):", $V_slice->length), 2);
    $support->log(sprintf($fmt1, "Identical clones:", $stats_chr{'identical'}), 2);
    $support->log(sprintf($fmt1, "Identical clones that were skipped:", $stats_chr{'skipped'}), 2);
    $support->log(sprintf($fmt1, "Clones with start/end mismatch:", $stats_chr{'mismatch'}), 2);
    $support->log(sprintf($fmt1, "Clones only in Ensembl:", $stats_chr{'E_only'}), 2);
    $support->log(sprintf($fmt1, "Clones only in Vega:", $stats_chr{'V_only'}), 2);
    $support->log(sprintf($fmt2, "Direct match coverage (Ensembl):", $stats_chr{'E_coverage'}), 2);
    $support->log(sprintf($fmt2, "Direct match coverage (Vega):", $stats_chr{'V_coverage'}), 2);

    # Aligned blocks
    if ($match->{$chr}) {
        $support->log("\nDirectly aligned blocks:\n\n", 1);
        $support->log(sprintf($fmt3, qw(E_START E_END E_CLONES V_START V_END V_CLONES)), 2);
        $support->log(('-'x67)."\n", 2);
        for (my $c = 0; $c < scalar(@{ $match->{$chr} }); $c++) {
            $support->log(sprintf($fmt4, @{ $match->{$chr}->[$c] }), 2);
            # sanity check: aligned region pairs must have same length
            my $e_len = $match->{$chr}->[$c]->[1] - $match->{$chr}->[$c]->[0] + 1;
            my $v_len = $match->{$chr}->[$c]->[4] - $match->{$chr}->[$c]->[3] + 1;
            $support->log_warning("Length mismatch: $e_len <> $v_len\n", 2) unless ($e_len == $v_len);
        }
    }

    # Non-aligned blocks
    if ($nomatch->{$chr}) {
        $support->log("\nNon-aligned blocks:\n\n", 1);
        $support->log(sprintf($fmt3, qw(E_START E_END E_CLONES V_START V_END V_CLONES)), 2);
        $support->log(('-'x67)."\n", 2);
        for (my $c = 0; $c < scalar(@{ $nomatch->{$chr} }); $c++) {
            $support->log(sprintf($fmt4, @{ $nomatch->{$chr}->[$c] }), 2);

            # find longest non-aligned block
            my $E_length = $nomatch->{$chr}->[$c]->[1] - $nomatch->{$chr}->[$c]->[0] + 1;
            my $V_length = $nomatch->{$chr}->[$c]->[4] - $nomatch->{$chr}->[$c]->[3] + 1;
            push @block_length, [$E_length, $V_length, $chr];
        }
    }

    $support->log_stamped("\nDone with chromosome $chr.\n", 1);
}

# add assembly.mapping to meta table
unless ($support->param('dry_run')) {
    $support->log("Adding assembly.mapping entry to meta table...\n");
    my $mappingstring = 'chromosome:'.$support->param('assembly').'|chromosome:'.$support->param('ensemblassembly');
    $E_dbh->do(qq(
        INSERT INTO meta (meta_key, meta_value)
        VALUES ('assembly.mapping', '$mappingstring')
    ));
    $support->log("Done.\n");
}

# overall stats
$support->log("\nOverall stats:\n");
$support->log(sprintf($fmt1, "Identical clones:", $stats_total{'identical'}), 1);
$support->log(sprintf($fmt1, "Identical clones that were skipped:", $stats_total{'skipped'}), 1);
$support->log(sprintf($fmt1, "Clones with start/end mismatch:", $stats_total{'mismatch'}), 1);
$support->log(sprintf($fmt1, "Clones only in Ensembl:", $stats_total{'E_only'}), 1);
$support->log(sprintf($fmt1, "Clones only in Vega:", $stats_total{'V_only'}), 1);

$support->log("\nNon-match block lengths:\n");
$support->log(sprintf($fmt3, qw(E_LENGTH V_LENGTH CHR)), 1);
$support->log(('-'x35)."\n", 1);
foreach my $block (sort { $a->[0] <=> $b->[0] } @block_length) {
    $support->log(sprintf("%10.0f  %10.0f %10s\n", @{ $block }), 1);
}

$support->log_stamped("\nDone.\n");

# finish logfile
$support->finish_log;


### end main


=head2 found_match

  Arg[1]      : String $chr - chromosome name 
  Arg[2]      : Hashref $match - datastructure to store aligned blocks
  Arg[3]      : Hashref $nomatch - datastructure to store non-aligned blocks
  Arg[4]      : Bio::EnsEMBL::ProjectionSegment $E_seg - current Ensembl segment
  Arg[5]      : Bio::EnsEMBL::ProjectionSegment $last_E_seg - last Ensembl
                segment
  Arg[6]      : Bio::EnsEMBL::ProjectionSegment $V_seg - current Vega segment
  Arg[7]      : Bio::EnsEMBL::ProjectionSegment $last_V_seg - last Vega segment
  Arg[8]      : Boolean $match_flag - flag indicating if last clone was a match
  Arg[9]      : Int $i - Vega clone count
  Arg[10]     : Int $j - Ensembl clone count
  Description : This function is called when two clones match (i.e. have the
                same name.version in both assemblies). Depending on the state
                of the last clone (match or nomatch), it extends aligned blocks
                or finishes the non-aligned block and creates a new aligned
                block.
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub found_match {
    my ($chr, $match, $nomatch, $E_seg, $last_E_seg, $V_seg, $last_V_seg, $match_flag, $i, $j) = @_;

    # last clone was a match
    if ($match_flag) {
        # adjust align block end
        if ($match->{$chr}) {
            my $c = scalar(@{ $match->{$chr} }) - 1;

            # if the gaps between this clone and the last are different, start
            # a new block
            if (($E_seg->from_start - $match->{$chr}->[$c]->[1]) !=
                ($V_seg->from_start - $match->{$chr}->[$c]->[4])) {

                $support->log("Gap size mismatch at chromosome $chr, E:".$match->{$chr}->[$c]->[1].'-'.$E_seg->from_start.', V:'.$match->{$chr}->[$c]->[4].'-'.$V_seg->from_start."\n", 2);

                # finish the last align block
                $match->{$chr}->[$c]->[1] = $last_E_seg->from_end;
                $match->{$chr}->[$c]->[2] = $j - $match->{$chr}->[$c]->[2];
                $match->{$chr}->[$c]->[4] = $last_V_seg->from_end;
                $match->{$chr}->[$c]->[5] = $i - $match->{$chr}->[$c]->[5];

                # start a new align block
                push @{ $match->{$chr} }, [
                    $E_seg->from_start,
                    $E_seg->from_end,
                    $j,
                    $V_seg->from_start,
                    $V_seg->from_end,
                    $i,
                ];

            # adjust align block end
            } else {
                $match->{$chr}->[$c]->[1] = $E_seg->from_end;
                $match->{$chr}->[$c]->[4] = $V_seg->from_end;
            }
        }
    
    # last clone was a non-match
    } else {
        # start a new align block
        push @{ $match->{$chr} }, [
            $E_seg->from_start,
            $E_seg->from_end,
            $j,
            $V_seg->from_start,
            $V_seg->from_end,
            $i,
        ];

        # finish the last non-align block
        if ($nomatch->{$chr}) {
            my $c = scalar(@{ $nomatch->{$chr} }) - 1;
            $nomatch->{$chr}->[$c]->[1] = $last_E_seg->from_end;
            $nomatch->{$chr}->[$c]->[2] = $j - $nomatch->{$chr}->[$c]->[2];
            $nomatch->{$chr}->[$c]->[4] = $last_V_seg->from_end;
            $nomatch->{$chr}->[$c]->[5] = $i - $nomatch->{$chr}->[$c]->[5];
        }
    }
}

=head2 found_nomatch

  Arg[1]      : String $chr - chromosome name 
  Arg[2]      : Hashref $match - datastructure to store aligned blocks
  Arg[3]      : Hashref $nomatch - datastructure to store non-aligned blocks
  Arg[4]      : Bio::EnsEMBL::ProjectionSegment $E_seg - current Ensembl segment
  Arg[5]      : Bio::EnsEMBL::ProjectionSegment $last_E_seg - last Ensembl
                segment
  Arg[6]      : Bio::EnsEMBL::ProjectionSegment $V_seg - current Vega segment
  Arg[7]      : Bio::EnsEMBL::ProjectionSegment $last_V_seg - last Vega segment
  Arg[8]      : Boolean $match_flag - flag indicating if last clone was a match
  Arg[9]      : Int $i - Vega clone count
  Arg[10]     : Int $j - Ensembl clone count
  Description : This function is called when two clones don't match (either
                different name.version or length mismatch in the two
                assemblies). Depending on the state of the last clone (nomatch
                or match), it extends non-aligned blocks or finishes the
                aligned block and creates a new non-aligned block.
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub found_nomatch {
    my ($chr, $match, $nomatch, $E_seg, $last_E_seg, $V_seg, $last_V_seg, $match_flag, $i, $j) = @_;

    # last clone was a match
    if ($match_flag) {
        # start a new non-align block
        push @{ $nomatch->{$chr} }, [
            $E_seg->from_start,
            undef,
            $j,
            $V_seg->from_start,
            undef,
            $i,
        ];

        # finish the last align block
        if ($nomatch->{$chr}) {
            my $c = scalar(@{ $match->{$chr} || [] }) - 1;
            $match->{$chr}->[$c]->[1] = $last_E_seg->from_end;
            $match->{$chr}->[$c]->[2] = $j - $match->{$chr}->[$c]->[2];
            $match->{$chr}->[$c]->[4] = $last_V_seg->from_end;
            $match->{$chr}->[$c]->[5] = $i - $match->{$chr}->[$c]->[5];
        }
    
    # last clone was a non-match
    } else {
        # adjust non-align block end
        if ($nomatch->{$chr}) {
            my $c = scalar(@{ $nomatch->{$chr} || [] }) - 1;
            $nomatch->{$chr}->[$c]->[1] = $E_seg->from_end;
            $nomatch->{$chr}->[$c]->[4] = $V_seg->from_end;
        }
    }
}

