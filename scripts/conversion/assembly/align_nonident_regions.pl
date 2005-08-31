#!/usr/local/bin/perl

=head1 NAME

align_nonident_regions.pl - create whole genome alignment between two closely
related assemblies for non-identical regions

=head1 SYNOPSIS

align_nonident_regions.pl [options]

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
    --evegadbname=NAME                  use ensembl-vega (target) database NAME
    --evegahost=HOST                    use ensembl-vega (target) database host
                                        HOST
    --evegaport=PORT                    use ensembl-vega (target) database port
                                        PORT
    --evegauser=USER                    use ensembl-vega (target) database
                                        username USER
    --evegapass=PASS                    use ensembl-vega (target) database
                                        passwort PASS
    --bindir=DIR                        look for program binaries in DIR

=head1 DESCRIPTION

This script is part of a series of scripts to transfer annotation from a
Vega to an Ensembl assembly. See "Related scripts" below for an overview of the
whole process.

It creates a whole genome alignment between two closely related assemblies for
non-identical regions. These regions are identified by another script
(align_by_clone_identity.pl) and stored in a temporary database table
(tmp_align).

Alignments are calculated by this algorithm:

    1. fetch region from tmp_align
    2. write soft-masked sequences to temporary files
    3. align using blastz
    4. filter best hits (for query sequences, i.e. Ensembl regions) using
       axtBest
    5. parse blastz output to create blocks of exact matches only
    6. remove overlapping target (Vega) alignments
    7. write alignments to assembly table

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
use File::Path;

$| = 1;

our $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
    'evegahost=s',
    'evegaport=s',
    'evegauser=s',
    'evegapass=s',
    'evegadbname=s',
    'bindir=s',
);
$support->allowed_params(
    $support->get_common_params,
    'evegahost',
    'evegaport',
    'evegauser',
    'evegapass',
    'evegadbname',
    'bindir',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $V_dba = $support->get_database('core');
my $V_dbh = $V_dba->dbc->db_handle;
my $V_sa = $V_dba->get_SliceAdaptor;
my $E_dba = $support->get_database('evega', 'evega');
my $E_dbh = $E_dba->dbc->db_handle;
my $E_sa = $E_dba->get_SliceAdaptor;

# create tmpdir to store input and output
my $user = `whoami`;
chomp $user;
our $tmpdir = "/tmp/$user.".time;
$support->log("Creating tmpdir $tmpdir...\n");
system("mkdir $tmpdir") == 0 or
    $support->log_error("Can't create tmp dir $tmpdir: $!\n");
$support->log("Done.\n");

# loop over non-aligned regions in tmp_align table
$support->log_stamped("Looping over non-aligned blocks...\n");
my $bindir = $support->param('bindir');
our %stats_total;
our $match;
our $fmt1 = "%-30s%10.0f (%3.2f%%)\n";
our $fmt2 = "%-30s%10.0f\n";
my $sth = $E_dbh->prepare(qq(SELECT * FROM tmp_align));
$sth->execute;
while (my $row = $sth->fetchrow_hashref) {
    my $id = $row->{'tmp_align_id'};

    $support->log_stamped("Block with tmp_align_id = $id\n", 1);
    my $E_slice = $E_sa->fetch_by_region(
        'chromosome',
        $row->{'seq_region_name'},
        $row->{'e_start'},
        $row->{'e_end'},
        1,
        $support->param('ensemblassembly'),
    );
    my $V_slice = $V_sa->fetch_by_region(
        'chromosome',
        $row->{'seq_region_name'},
        $row->{'v_start'},
        $row->{'v_end'},
        1,
        $support->param('assembly'),
    );

    # write sequences to file
    $support->log("Writing sequences to fasta and nib files...\n", 2);
    my $E_fh = $support->filehandle('>', "$tmpdir/e_seq.$id.fa");
    my $V_fh = $support->filehandle('>', "$tmpdir/v_seq.$id.fa");
    print $E_fh join(':', ">e_seq.$id dna:chromfrag chromosome",
                          $support->param('ensemblassembly'),
                          $E_slice->start,
                          $E_slice->end,
                          $E_slice->strand
                    ), "\n";
    print $E_fh $E_slice->get_repeatmasked_seq(undef, 1)->seq, "\n";
    close($E_fh);
    print $V_fh join(':', ">v_seq.$id dna:chromfrag chromosome",
                          $support->param('assembly'),
                          $V_slice->start,
                          $V_slice->end,
                          $V_slice->strand
                    ), "\n";
    print $V_fh $V_slice->get_repeatmasked_seq(undef, 1)->seq, "\n";
    close($V_fh);

    # convert sequence files from fasta to nib format (needed for lavToAxt)
    system("$bindir/faToNib $tmpdir/e_seq.$id.fa $tmpdir/e_seq.$id.nib") == 0 or
        $support->log_error("Can't run faToNib: $!\n");
    system("$bindir/faToNib $tmpdir/v_seq.$id.fa $tmpdir/v_seq.$id.nib") == 0 or
        $support->log_error("Can't run faToNib: $!\n");
    $support->log("Done.\n", 2);

    # align using blastz
    $support->log("Running blastz...\n", 2);
    my $blastz_cmd = qq($bindir/blastz $tmpdir/e_seq.$id.fa $tmpdir/v_seq.$id.fa Q=blastz_matrix.txt T=0 L=10000 H=2200 Y=3400 > $tmpdir/blastz.$id.lav);
    system($blastz_cmd) == 0 or $support->log_error("Can't run blastz: $!\n");
    $support->log("Done.\n", 2);

    # convert blastz output from lav to axt format
    $support->log("Converting blastz output from lav to axt format...\n", 2);
    system("$bindir/lavToAxt $tmpdir/blastz.$id.lav $tmpdir $tmpdir $tmpdir/blastz.$id.axt") == 0 or $support->log_error("Can't run lavToAxt: $!\n");
    $support->log("Done.\n", 2);

    # find best alignment with axtBest
    $support->log("Finding best alignment with axtBest...\n", 2);
    system("$bindir/axtBest $tmpdir/blastz.$id.axt all $tmpdir/blastz.$id.best.axt") == 0 or $support->log_error("Can't run axtBest: $!\n");
    $support->log("Done.\n", 2);

    # parse blastz output
    $support->log("Parsing blastz output...\n", 2);
    # read file
    my $fh = $support->filehandle('<', "$tmpdir/blastz.$id.best.axt");
    my $i = 1;
    my ($header, $e_seq, $v_seq, %stats);
    map { $stats{$_} = 0 } qw(match mismatch gap);
    while (my $line = <$fh>) {
        # there are blocks of 4 lines, where line 1 is the header, line 2 is
        # e_seq, line3 is v_seq
        $header = $line unless (($i-1) % 4);
        $e_seq = $line unless (($i-2) % 4);
        chomp $e_seq;
        my @e_arr = split(//, $e_seq);
        $v_seq = $line unless (($i-3) % 4);
        chomp $v_seq;
        my @v_arr = split(//, $v_seq);

        # compare sequences letter by letter
        if ($i % 4 == 0) {
            my $match_flag = 0;
            map { $stats{$_} = 0 } qw(e_gap v_gap);
            my %coords;
            @coords{'e_start', 'e_end', 'v_start', 'v_end', 'strand'} =
                (split(/ /, $header))[2, 3, 5, 6, 7];
            ($coords{'strand'} eq '+') ? ($coords{'strand'} = 1) :
                                         ($coords{'strand'} = -1);
            for (my $j = 0; $j < scalar(@e_arr); $j++) {
                # gap
                if ($e_arr[$j] eq '-' or $v_arr[$j] eq '-') {
                    $stats{'gap'}++;
                    $stats{'e_gap'}++ if ($e_arr[$j] eq '-');
                    $stats{'v_gap'}++ if ($v_arr[$j] eq '-');
                    $match_flag = 0;
                } else {
                    # match
                    if ($e_arr[$j] eq $v_arr[$j]) {
                        &found_match($row->{'seq_region_name'}, $id, $stats{'alignments'}, $match_flag, $j, \%stats, \%coords);
                        $stats{'match'}++;
                        $match_flag = 1;
                    # mismatch
                    } else {
                        $stats{'mismatch'}++;
                        $match_flag = 0;
                    }
                }
            }
            $stats{'bp'} += scalar(@e_arr);
            $stats{'alignments'}++;
        }
        
        $i++;
    }

    # convert relative alignment coordinates to chromosomal coords
    my $chr = $row->{'seq_region_name'};
    for (my $align = 0; $align < scalar(@{ $match->{$chr}->{$id} }); $align++) {
        for (my $c = 0; $c < scalar(@{ $match->{$chr}->{$id}->[$align] }); $c++) {
            $match->{$chr}->{$id}->[$align]->[$c]->[0] += $row->{'e_start'} - 1;
            $match->{$chr}->{$id}->[$align]->[$c]->[1] += $row->{'e_start'} - 1;

            # forward strand match
            if ($match->{$chr}->{$id}->[$align]->[$c]->[4] == 1) {
                $match->{$chr}->{$id}->[$align]->[$c]->[2] += $row->{'v_start'} - 1;
                $match->{$chr}->{$id}->[$align]->[$c]->[3] += $row->{'v_start'} - 1;
            
            # reverse strand match
            } else {
                my $tmp_start = 
                    $row->{'v_end'} - $match->{$chr}->{$id}->[$align]->[$c]->[3] + 1;
                $match->{$chr}->{$id}->[$align]->[$c]->[3] =
                    $row->{'v_end'} - $match->{$chr}->{$id}->[$align]->[$c]->[2] + 1;
                $match->{$chr}->{$id}->[$align]->[$c]->[2] = $tmp_start;
            }

            # sanity check: aligned region pairs must have same length
            my $e_len = $match->{$chr}->{$id}->[$align]->[$c]->[1] - $match->{$chr}->{$id}->[$align]->[$c]->[0];
            my $v_len = $match->{$chr}->{$id}->[$align]->[$c]->[3] - $match->{$chr}->{$id}->[$align]->[$c]->[2];
            $support->log_warning("Length mismatch: $e_len <> $v_len in block $id, alignment $align, stretch $c\n", 2) unless ($e_len == $v_len);
        }
    }

    $support->log("Done.\n", 2);

    # log alignment stats
    $support->log("Blastz alignment stats:\n", 2);
    $support->log(sprintf($fmt2, "Alignments:", $stats{'alignments'}), 3);
    $support->log(sprintf($fmt1, "Matches:", $stats{'match'}, $stats{'match'}/$stats{'bp'}*100), 3);
    $support->log(sprintf($fmt1, "Mismatches:", $stats{'mismatch'}, $stats{'mismatch'}/$stats{'bp'}*100), 3);
    $support->log(sprintf($fmt1, "Gaps:", $stats{'gap'}, $stats{'gap'}/$stats{'bp'}*100), 3);
    map { $stats_total{$_} += $stats{$_} } qw(match mismatch gap bp);

    $support->log_stamped("Done with block $id.\n", 1);
}
$support->log_stamped("Done.\n");

# filter overlapping Vega alignment regions
$support->log_stamped("Filtering overlapping Vega alignment regions...\n");
&filter_overlaps;
$support->log_stamped("Done.\n");

# write alignments to assembly table
# store directly aligned blocks in assembly table
unless ($support->param('dry_run')) {
    my $sth = $E_dbh->prepare(qq(
        INSERT INTO assembly (asm_seq_region_id, cmp_seq_region_id, asm_start,
            asm_end, cmp_start, cmp_end, ori)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ));
    $support->log("Adding assembly entries for alignments...\n");
    my $i;
    foreach my $chr (sort _by_chr_num keys %{ $match }) {
        # get seq_region_id for Ensembl and Vega chromosome
        my $V_sid = $E_sa->get_seq_region_id($E_sa->fetch_by_region('chromosome', $chr, undef, undef, undef, $support->param('assembly')));
        my $E_sid = $E_sa->get_seq_region_id($E_sa->fetch_by_region('chromosome', $chr, undef, undef, undef, $support->param('ensemblassembly')));

        foreach my $id (sort { $a <=> $b } keys %{ $match->{$chr} }) {
            for (my $align = 0; $align < scalar(@{ $match->{$chr}->{$id} }); $align++) {
                for (my $c = 0; $c < scalar(@{ $match->{$chr}->{$id}->[$align] }); $c++) {
                    if ($match->{$chr}->{$id}->[$align]->[$c]) {
                        $sth->execute(
                            $V_sid,
                            $E_sid,
                            $match->{$chr}->{$id}->[$align]->[$c]->[2],
                            $match->{$chr}->{$id}->[$align]->[$c]->[3],
                            $match->{$chr}->{$id}->[$align]->[$c]->[0],
                            $match->{$chr}->{$id}->[$align]->[$c]->[1],
                            $match->{$chr}->{$id}->[$align]->[$c]->[4],
                        );
                        $i++;
                    }
                }
            }
        }
    }
    $support->log("Done inserting $i entries.\n");
}


# cleanup
$support->log_stamped("\nRemoving tmpdir...\n");
rmtree($tmpdir) or $support->log_warning("Could not delete $tmpdir: $!\n");
$support->log_stamped("Done.\n");

# drop tmp_align
unless ($support->param('dry_run')) {
    if ($support->user_proceed("Would you like to drop the tmp_align table?")) {
        $support->log_stamped("Dropping tmp_align table...\n");
        $E_dbh->do(qq(DROP TABLE tmp_align));
        $support->log_stamped("Done.\n");
    }
}

# overall stats
# blastz
$support->log("\nOverall blastz alignment stats:\n");
$support->log(sprintf($fmt1, "Matches:", $stats_total{'match'}, $stats_total{'match'}/$stats_total{'bp'}*100), 1);
$support->log(sprintf($fmt1, "Mismatches:", $stats_total{'mismatch'}, $stats_total{'mismatch'}/$stats_total{'bp'}*100), 1);
$support->log(sprintf($fmt1, "Gaps:", $stats_total{'gap'}, $stats_total{'gap'}/$stats_total{'bp'}*100), 1);

# alignments to be written to assembly table
$support->log_verbose("\nAlignments that will be written to assembly table:\n");
my $fmt3 = "%-8s%-12s%-5s%-10s%-10s%-10s%-10s\n";
my $fmt4 = "%-8s%-12s%-5s%8.0f  %8.0f  %8.0f  %8.0f\n";
$support->log_verbose(sprintf($fmt3, qw(CHR BLOCK ALIGNMENT E_START E_END V_START V_END)), 1);
$support->log_verbose(('-'x63)."\n", 1);
foreach my $chr (sort _by_chr_num keys %{ $match }) {
    foreach my $id (sort { $a <=> $b } keys %{ $match->{$chr} }) {
        for (my $align = 0; $align < scalar(@{ $match->{$chr}->{$id} }); $align++) {
            for (my $c = 0; $c < scalar(@{ $match->{$chr}->{$id}->[$align] }); $c++) {
                if ($match->{$chr}->{$id}->[$align]->[$c]) {
                    $support->log_verbose(sprintf($fmt4, $chr, $id, $align+1, @{ $match->{$chr}->{$id}->[$align]->[$c] }), 1);
                    my $l = $match->{$chr}->{$id}->[$align]->[$c]->[1] - $match->{$chr}->{$id}->[$align]->[$c]->[0];
                    $stats_total{'alignments'}++;
                    $stats_total{'short1_10'}++ if ($l < 11);
                    $stats_total{'short11_100'}++ if ($l > 10 and $l < 101);
                }
            }
        }
    }
}
$support->log("\nAssembly entry stats:\n");
$support->log(sprintf($fmt2, "Total alignment blocks:", $stats_total{'alignments'}), 1);
$support->log(sprintf($fmt2, "Alignments 1-10 bp:", $stats_total{'short1_10'}), 1);
$support->log(sprintf($fmt2, "Alignments 11-100 bp:", $stats_total{'short11_100'}), 1);

# finish logfile
$support->finish_log;


### END main


=head2 found_match

  Arg[1]      : String $chr - the chromosome name
  Arg[2]      : Int $id - block number (corresponds to tmp_align.tmp_align_id)
  Arg[3]      : Int $align - the alignment number in the blastz output
  Arg[4]      : Boolean $match_flag - flag indicating if last bp was a match
  Arg[5]      : Int $j - current bp position in the alignment
  Arg[6]      : Hashref $stats - datastructure for collecting alignment stats
  Arg[7]      : Hashref $coords - alignment coordinates and strand from blastz
                output
  Description : Populates a datastructure describing blocks of alignment
  Return type : none (global datastructure $match will be populated)
  Exceptions  : none
  Caller      : internal

=cut

sub found_match {
    my ($chr, $id, $align, $match_flag, $j, $stats, $coords) = @_;

    # last position was a match
    if ($match_flag) {
        # adjust align block end
        if ($match->{$chr}->{$id}->[$align]) {
            my $c = scalar(@{ $match->{$chr}->{$id}->[$align] }) - 1;
            $match->{$chr}->{$id}->[$align]->[$c]->[1] =
                $coords->{'e_start'} + $j - $stats->{'e_gap'};
            $match->{$chr}->{$id}->[$align]->[$c]->[3] =
                $coords->{'v_start'} + $j - $stats->{'v_gap'};
        }
    
    # last position was a non-match
    } else {
        # start a new align block
        push @{ $match->{$chr}->{$id}->[$align] }, [
            $coords->{'e_start'} + $j - $stats->{'e_gap'},
            $coords->{'e_start'} + $j - $stats->{'e_gap'},
            $coords->{'v_start'} + $j - $stats->{'v_gap'},
            $coords->{'v_start'} + $j - $stats->{'v_gap'},
            $coords->{'strand'},
        ];
    }
}

=head2 filter_overlaps

  Description : Filters overlapping target (i.e. Vega) sequences in alignments.
                Longer alignments are preferred.
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub filter_overlaps {
    foreach my $chr (sort keys %{ $match }) {
        # rearrange the datastructure so that we can find overlaps
        my $coord_check;
        foreach my $id (keys %{ $match->{$chr} }) {
            for (my $align = 0; $align < scalar(@{ $match->{$chr}->{$id} }); $align++) {
                for (my $c = 0; $c < scalar(@{ $match->{$chr}->{$id}->[$align] }); $c++) {
                    push @{ $coord_check }, [
                        $match->{$chr}->{$id}->[$align]->[$c]->[0],
                        $match->{$chr}->{$id}->[$align]->[$c]->[1],
                        $match->{$chr}->{$id}->[$align]->[$c]->[2],
                        $match->{$chr}->{$id}->[$align]->[$c]->[3],
                        $id,
                        $align,
                        $c,
                    ];
                }
            }
        }
        
        my @e_sort = sort { $a->[0] <=> $b->[0] } @{ $coord_check };
        my @v_sort = sort { $a->[2] <=> $b->[2] } @{ $coord_check };

        # sanity check: Ensembl alignments must not overlap (axtBest should
        # guarantee that)
        my $last;
        foreach my $c (@e_sort) {
            $support->log_warning("Overlapping Ensembl alignment at ".join(':', $chr, $c->[0], $c->[1])." (last_end ".$last->[1].")\n", 1) if ($last and $c->[0] <= $last->[1]);
            $last = $c;
        }

        # now filter Vega overlaps
        my ($last, @seen);
        foreach my $c (@v_sort) {
            if ($last and $c->[2] <= $last->[3]) {
                $support->log_verbose("Overlapping Vega alignment at ".join(':', $chr, $c->[2], $c->[3])." (last_end ".$last->[3].")\n", 1);

                # if last alignment was longer, delete this one
                if ($last->[3]-$last->[2] > $c->[3]-$c->[2]) {
                    undef $match->{$chr}->{$c->[4]}->[$c->[5]]->[$c->[6]];

                # if last alignment was shorter, trace back and delete all
                # overlapping shorter alignments
                } else {
                    foreach my $s (@seen) {
                        # earlier alignment still overlapping
                        if ($c->[2] <= $s->[3]) {
                            # earlier alignment shorter -> delete it
                            if ($s->[3]-$s->[2] < $c->[3]-$c->[2]) {
                                undef $match->{$chr}->{$s->[4]}->[$s->[5]]->[$s->[6]];

                            # this alignment shorter -> delete it
                            } else {
                                undef $match->{$chr}->{$c->[4]}->[$c->[5]]->[$c->[6]];
                                $last = $s;
                                last;
                            }
                        } else {
                            $last = $s;
                            last;
                        }
                    }                
                    
                    $last = $c;
                }
            }
            unshift @seen, $c;
            $last = $c unless ($last);
        }
    }
}

=head2 _by_chr_num

  Example     : my @sorted = sort _by_chr_num qw(X, 6-COX, 14, 7);
  Description : Subroutine to use in sort for sorting chromosomes. Sorts
                numerically, then alphabetically
  Return type : values to be used by sort
  Exceptions  : none
  Caller      : internal

=cut

sub _by_chr_num {
    my @awords = split /-/, $a;
    my @bwords = split /-/, $b;

    my $anum = $awords[0];
    my $bnum = $bwords[0];

    if ($anum !~ /^[0-9]*$/) {
        if ($bnum !~ /^[0-9]*$/) {
            return $anum cmp $bnum;
        } else {
            return 1;
        }
    }
    if ($bnum !~ /^[0-9]*$/) {
        return -1;
    }

    if ($anum <=> $bnum) {
        return $anum <=> $bnum;
    } else {
        if ($#awords == 0) {
            return -1;
        } elsif ($#bwords == 0) {
            return 1;
        } else {
            return $awords[1] cmp $bwords[1];
        }
    }
}

