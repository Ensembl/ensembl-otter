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


# wrapper that loads agps from chromoview (with QC check of project_status),
# checks them for redundant clones, loads them into otter, loads assembly tags
# and realigns genes...uff
# it also does this for haplotypic clones
#
# 17.11.2005 Kerstin Howe (kj2)
# last updated
# 29.09.2009 Britt Reimholz (br2)
# 23.03.2010 br2
#
# if you want to delete a sequence_set use
# /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/delete_sequence_set.pl
# -host otterpipe2 -port 3323 -user ottadmin -pass ********** -dbname pipe_zebrafish -delete -set set1 -set set2 etc.

use strict;
use warnings;

use Carp;
use Getopt::Long;
use DBI;

use FindBin qw($Bin);
my $AnacodeBin = "/software/anacode/bin";

my ($date,$test,$verbose,$skip,$haplo,$tags,$help,$stop,$chroms,$path, $logfile, $noload);
my $loutrehost = 'otterlive';
my $loutrename = 'loutre_zebrafish';
## not needed any more:
#my $loutreuser = 'ottadmin';
#my $loutrepass;
#my $loutreport = 3324;

my $pipehost   = 'otterpipe2';
my $pipename   = 'pipe_zebrafish';
#my $pipeuser   = 'ottadmin';
my $pipeuser   = 'ottro';
my $pipepass   = '';
my $pipeport   = 3323;

GetOptions(
    'date:s'     => \$date,       # format YYMMDD
    'test'       => \$test,       # doesn't execute system commands
    'verbose'    => \$verbose,    # prints all commands
    'skip:s'     => \$skip,       # skips certain steps
    'tags'       => \$tags,       # loads assembly tags
    'h'          => \$help,       # help
    'stop'       => \$stop,       # stops where you've put your exit(0) if ($stop)
    'haplo'      => \$haplo,      # deals with chr H clones (only)
    'chr:s'      => \$chroms,     # overrides all chromosomes
    'path:s'     => \$path,       # overrides /lustre/cbi4/work1/zfish/agps
    'logfile:s'  => \$logfile,    # overrides ./agp_$date.log
    'noload'     => \$noload,     # doesn't load into dbs, only creates files
    'loutrehost' => \$loutrehost, # default: otterlive
    'loutrename' => \$loutrename, # default: loutre_zebrafish
    'pipehost'   => \$pipehost,   # default: otterpipe2
    'pipename'   => \$pipename,   # default: pipe_zebrafish
    'pipeuser'   => \$pipeuser,   # default: ottro
    'pipepass'   => \$pipepass,   # password for user ottro
    'pipeport'   => \$pipeport,   # default: 3323
);
#    'loutreuser' => \$loutreuser, # default: ottadmin
#    'loutrepass' => \$loutrepass, # default: password for user ottadmin
#    'loutreport' => \$loutreport, # default: 3324

my @chroms = split /,/, $chroms if ($chroms);
$skip = '' unless $skip;

## was:    print "                    -skip            # skip steps in order agp, region, fullagp, load\n";
## commented out: -skip realign
if (($help) || (!$date)){
    print "build_zfish_agps.pl -date YYMMDD\n";
    print "                    -skip       # skip steps in order agp, region, newagp, load\n";
    print "                    -haplo      # loads chr H clones\n";
    print "                    -chr        # runs for your comma separated list of chromosomes\n";
    print "                    -path       # path to build new agp folder in\n";
    print "                    -logfile    # default logfile: ./agp_DATE.log)\n";
    print "                    -tags       # load assembly tags\n";
    print "                    -test       # don't execute system commands\n";
    print "                    -verbose    # print commands\n";
    print "                    -noload     # do ot load paths into databases\n";
    print "                    -loutrehost # default: otterlive\n";
    print "                    -loutrename # default: loutre_zebrafish\n";
    print "                    -pipehost   # default: otterpipe2\n";
    print "                    -pipename   # default: pipe_zebrafish\n";
    print "                    -pipeuser   # default: ottadmin\n";
    print "                    -pipepass   # \n";
    print "                    -pipeport   # default: 3323\n";
}
#    print "                    -loutreuser # default: ottadmin\n";
#    print "                    -loutrepass # \n";
#    print "                    -loutreport # default: 3324\n";

# date
die "Date doesn't have format YYMMDD\n" unless ($date =~ /\d{6}/);
my ($year,$month,$day) = ($date =~ /(\d\d)(\d\d)(\d\d)/);
my $moredate = "20".$date;
my $fulldate = $day.".".$month.".20".$year;

# log file
$logfile = "agp_$date.log" unless ($logfile);
$logfile = "haplo_$logfile" if ($haplo);
open(LOG, ">$logfile") or die "Can't write to log file $logfile : $!";

my $logfile_load_tags = $logfile;
if ($logfile_load_tags =~ /\.log/) {
  $logfile_load_tags =~ s/\.log/_load_tags.log/g;
} else {
  $logfile_load_tags .= ".load_tags";
}

# paths
$path = "/lustre/cbi4/work1/zfish/agps" unless ($path);
my $agp = "agp_".$date;
my $agpdir;
$agpdir = $path."/".$agp       unless ($haplo);
$agpdir = $path."/haplo_".$agp if ($haplo);
@chroms = (1..25,"U") unless (@chroms);

mkdir($agpdir,0777) or die "ERROR: Cannot make agp_$date $!\n" unless (($test) || ($skip =~ /\S+/));
chdir($agpdir);


# GET AGPS
unless (($skip =~ /agp/) || ($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command = join ' ',
	  ("$AnacodeBin/oracle2agp -catch_err -species Zebrafish -pstatuses 35,44,48 -chromosome $chr",
	   ($haplo ? ("-subregion H_$chr") : ()), "> $agpdir/chr".$chr.".agp");
        runit($command, "ignore");
    }
    print LOG "\n";
    ## check if agps are empty or clones are in more than one chromosome:
    &check_agps unless ($tags);
}
# if agps don't load, identify showstoppers, introduce a gap before or after in tpf (check chromoview to decide where)
# use tpf2oracle -species zebrafish -chr n chrn.tpf to upload, then dump agp again
# alert finishers!


# CREATE REGION FILES
unless (($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command = "$Bin/make_agps_for_otter_sets.pl -agp $agpdir/chr".$chr.".agp";
        $command .= " -haplo" if ($haplo);
        $command .= " > chr".$chr.".region";
        runit($command, "ignore");
    }
    print LOG "\n";

    # create only one agp.new file for chr H
    if ($haplo) {
        open(OUT,">$agpdir/chrH.region") or die "ERROR: Cannot open $agpdir/chrH.region $!\n";
        foreach my $chr (@chroms) {
            my $line = "N	500000\n";
            my $file = "chr".$chr.".region";
            open(IN,"$agpdir/$file") or die "ERROR: Cannot open $agpdir/$file $!\n";
            while (<IN>) {
                print OUT;
            }
            print OUT $line;
        }
	print LOG "concatenated all region files into chrH.region\n\n";
    }
}
#CONVERT REGION FILES TO AGP
# start here with -skip region
unless (($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {
        my $command = "$AnacodeBin/regions_to_agp -chromosome $chr $agpdir/chr".$chr.".region > $agpdir/chr".$chr.".fullagp";
        runit($command, "ignore");
    }
    print LOG "\n";
}


# GET MISSING CLONE SEQUENCES
unless (($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    chdir($agpdir);
    my $command1 = "$Bin/get_missing_clone_seqs.pl";
    runit($command1);
    print LOG "\n";
}
# stop here if flag 'noload' is chosen.
die("Stopping: You chose not to load the agps into the database\n") if ($noload);

# to load directly from agp into new pipedb and loutr db
# perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chrH_20090616 -description chrH_20090616 -host otterpipe2 -user ottadmin -pass ********** -port 3323 -dbname pipe_zebrafish_new ../haplo_agp_090616/chrH.fullagp
# perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chrH_20090616 -description chrH_20090616 -host otterlive -user ottadmin -pass ********** -port 3324 -dbname loutre_zebrafish ../haplo_agp_090616/chrH.fullagp


# LOAD AGPS INTO LOUTRE_ZEBRAFISH AND PIPE_ZEBRAFISH
# start here with -skip newagp
unless (($skip =~ /load/) || ($skip =~ /realign/)) {
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {

#      my $command = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_loutre_pipeline.pl -set chr".$chr."_".$moredate." -description \"chrom ".$chr."\" -dbname loutre_zebrafish $agpdir/chr".$chr.".fullagp";
#      my $pipeload  = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chr".$chr."_".$moredate." -description chr".$chr."_".$moredate." -host $pipehost -user $pipeuser -pass $pipepass -port $pipeport -dbname $pipename $agpdir/chr".$chr.".fullagp";
#      my $otterload = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chr".$chr."_".$moredate." -description chr".$chr."_".$moredate." -host $loutrehost -user $loutreuser -pass $loutrepass -port $loutreport -dbname $loutrename $agpdir/chr".$chr.".fullagp";

## load_from_agp.pl was replaced by load_loutre_pipeline.pl; this script can load both databases:
      my $otterload = "/software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_loutre_pipeline.pl  -set chr" . $chr . "_" . $moredate . " -description chr" . $chr . "_" . $moredate . " -host $loutrehost -dbname $loutrename -do_pipe $agpdir/chr" . $chr . ".fullagp";

#      runit($pipeload, "ignore");
      runit($otterload, "ignore");
    }
    print LOG "\n";

    &compare_final_numbers;
}

if ($haplo) {
    die "\nEND OF: This is it for haplotype chromosomes, but you might want to set the otter sequence entries and alert anacode to start the analyses\n";
}

my $text = "\nthis is it for the moment, you need to load the assembly tags\n";
$text   .= "perl /software/anacode/otter/otter_production_main/ensembl-otter/scripts/lace/fetch_assembly_tags_for_loutre -dataset zebrafish -verbose -update -misc -atag > $logfile_load_tags\n";
$text   .= "make new clone_sets visible by running the following command in loutre\n";
$text   .= "update seq_region_attrib sra, seq_region sr set sra.value = 0 where sra.attrib_type_id = 129 and sra.seq_region_id = sr.seq_region_id and sr.name like \'\%".$date."\';\n";
print  $text;
print LOG $text;
print "all done";

# REALIGN GENES
# start here with -skip load
#my $command2 = "touch realign_offtrack_genes.out";
#runit($command2);
#unless ($skip =~ /realign/) {
#    foreach my $chr (@chroms) {
#        my $command = "\n$AnacodeBin/realign_offtrack_genes -dataset zebrafish -set chr".$chr."_".$moredate." >> & realign_offtrack_genes.out";
#        my $command = "\n/software/anacode/pipeline/ensembl-pipeline/scripts/Finished/assembly/align_by_component_identity.pl -dataset zebrafish -set chr".$chr."_".$moredate." >> & realign_offtrack_genes.out";
#        runit($command);
#    }
#
#}

# do this
# cd /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/assembly/
#
# foreach i (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 H U)
#   perl align_by_component_identity.pl -host otterlive -port 3324 -user ottroot -pass ********** -dbname loutre_zebrafish \
#   -assembly Otter -altassembly Otter -chromosomes chr${i}_20080117 -altchromosomes chr${i}_20080214 > & /lustre/cbi4/work1/zfish/agps/agp_080214/transfer${i}.log
# end
#
# foreach i (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 H U)
#   perl align_nonident.pl -host otterlive -port 3324 -user ottroot -pass ********** -dbname loutre_zebrafish -assembly Otter -altassembly Otter \
#   -chromosomes chr${i}_20080117 -altchromosomes chr${i}_20080214 > & /lustre/cbi4/work1/zfish/agps/agp_080214/transferb${i}.log
# end



### LOAD ASSEMBLY TAGS
### start here with -skip realign
##if ($tags) {
##    my $command2 = "perl /nfs/team71/zfish/kj2/new_cvs/ensembl-otter/scripts/lace/fetch_assembly_tags_for_loutre -dataset zebrafish -verbose -update -misc -atag";
##    runit($command2);
##}

# make new sets visible
# first check
# select sr.name, sra.attrib_type_id, sra.value from seq_region sr, seq_region_attrib sra where sr.seq_region_id = sra.seq_region_id and sr.name like '%080214';
# update seq_region_attrib sra, seq_region sr set sra.value = 0 where sra.seq_region_id = sr.seq_region_id and sra.attrib_type_id = 129 and sr.name like '%080207';
########################################################

sub runit {
    my ($command, $ignore_errs) = @_;
    print LOG $command,"\n";
    return if $test;

    if (system("$command")) {
	my $err = ($? == -1 ? "error $!" : sprintf('returncode 0x%04x', $?));
	$err .= ", called from ".(join " line ", (caller())[1, 2]);
	print LOG " # Failed: $err\n";
	if ($ignore_errs) {
	    warn "Ignoring error from $command\n\t\t$err\n";
	} else {
	    die "ERROR: Cannot execute $command $err\n";
	}
    } # else success
}


## check if agps are empty or clones are in more than one chromosome
sub check_agps {
    my %seen;
    foreach my $chr (@chroms) {
        my $file = "chr".$chr.".agp";
        open(IN,"$agpdir/$file") or die "ERROR: Cannot open $agpdir/$file $!\n";
        while (<IN>) {
            unless (/\S+/) {
                warn "ERROR: chr".$chr.".agp is empty\n";
            }
            my @a = split /\s+/;
            print STDERR  "ODD LINE in $file:\n$_" unless (exists $a[5]);
            $seen{$a[5]}++ unless ($a[5] =~ /^\d+$/);
        }
    }
    my $alarm;
    foreach my $clone (keys %seen) {
        if ($seen{$clone} > 1) {
            print STDERR "ERROR: $clone is in more than one chromosome\n";
            $alarm++;
        }
    }
    die "ERROR: agps are incorrect\n" if ($alarm && ($alarm > 0));
}

## check results, compare numbers of last path against current one
sub compare_final_numbers {

    #get db connection
    my $dbh_pipe = DBI->connect("DBI:mysql:$pipename:$pipehost:$pipeport", $pipeuser, $pipepass) or die "Can't connect to database: $DBI::errstr\n";
#   $dbh_pipe->trace(1);

    ## get second last date for a/any chromosome:
    my $ary_ref = $dbh_pipe->selectcol_arrayref(qq(select name from seq_region where name like 'chr4%' order by name desc));
    my $old_date;
    if ((defined @$ary_ref) and (defined ${$ary_ref}[1])) {
        $old_date =  ${$ary_ref}[1];
        $old_date =~ s/chr4_//;
    } else {
        print STDERR "WARNING: couldn't find date of last tile path \n";
    }

    my (%numbers_of_clones_old, %numbers_of_clones_new);
    my $sql = qq(SELECT sr.name, count(*) from assembly a, seq_region sr where sr.seq_region_id = a.asm_seq_region_id and sr.name like ? group by sr.name);
    my $sth = $dbh_pipe->prepare($sql);
    print LOG "\nquery pipe db with following sql:\n" . $sql . "\nfor $moredate and $old_date\n" if ($verbose);

    $sth->execute(qq(%$old_date)) or print STDERR "WARNING: couldn't select tile path for date $old_date: \n$DBI::errstr \n";
    while (my $ref = $sth->fetchrow_arrayref()) {
        my $chromosome = @{$ref}[0];
        $chromosome =~ s/_$old_date//;
        $numbers_of_clones_old{$chromosome} = @{$ref}[1];
    }

    $sth->execute(qq(%$moredate)) or print STDERR "WARNING: couldn't select tile path for date $moredate: \n$DBI::errstr \n";
    while (my $ref = $sth->fetchrow_arrayref()) {
        my $chromosome = @{$ref}[0];
        $chromosome =~ s/_$moredate//;
        $numbers_of_clones_new{$chromosome} = @{$ref}[1];
    }

    print LOG "\nThe following lists for each chromosome the number of clones on the tile path: $old_date / $moredate\n" if ($verbose);
    foreach my $chromosome (keys %numbers_of_clones_new) {
        my $number_new = $numbers_of_clones_new{$chromosome};
        my $number_old = $numbers_of_clones_old{$chromosome};
        print LOG "$chromosome: $number_old / $number_new\n" if ($verbose);
        if (($number_old > $number_new) && ($chromosome =~ /\d/)) {
    	print STDERR "WARNING: the number of clones for chromosome $chromosome look wrong ($moredate: $number_new, $old_date: $number_old), please check! \n";
    	print LOG "WARNING: the number of clones for chromosome $chromosome look wrong ($moredate: $number_new, $old_date: $number_old), please check! \n";
        }
    }

}
