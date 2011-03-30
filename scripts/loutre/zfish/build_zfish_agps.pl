#!/software/bin/perl -w

# wrapper that loads agps from chromoview, checks them for redundant clones, 
# then against qc checked clones, loads them into otter, loads assembly tags
# and realigns genes...uff
# it also does this for haplotypic clones
#
# 17.11.2005 Kerstin Howe (kj2)
#
# if you want to delete a sequence_set use
# /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/delete_sequence_set.pl 
# -host otterpipe2 -port 3303 -user ottadmin -pass wibble -dbname pipe_zebrafish -delete -set set1 -set set2 etc.

use strict;
use Getopt::Long;

my ($date,$test,$verbose,$skip,$haplo,$tags,$help,$stop,$chroms,$path, $noload);
GetOptions(
        'date:s'   => \$date,       # format YYMMDD 
        'test'     => \$test,       # doesn't execute system commands
        'verbose'  => \$verbose,    # prints all commands 
        'skip:s'   => \$skip,       # skips certain steps
        'tags'     => \$tags,       # loads assembly tags
        'h'        => \$help,       # help
        'stop'     => \$stop,       # stops where you've put your exit(0) if ($stop)
        'haplo'    => \$haplo,      # deals with chr H clones (only)
        'chr:s'    => \$chroms,     # overrides all chromosomes
        'path:s'   => \$path,       # overrides /lustre/cbi4/work1/zfish/agps
        'noload'   => \$noload,     # doesn't load into dbs, only creates files
);

my @chroms = split /,/, $chroms if ($chroms);
$skip = '' unless $skip;

if (($help) || (!$date)){
    print "build_zfish_agps.pl -date YYMMDD\n";
    print "                    -skip            # skip steps in order agp, qc, region, fullagp, load\n";
    print "                    -haplo           # loads chr H clones\n";
    print "                    -chr             # runs for your comma separated list of chromosomes\n";
    print "                    -path            # path to build new agp folder in\n";
    print "                    -tags            # load assembly tags\n";
    print "                    -test            # don't execute system commands\n";
    print "                    -verbose         # print commands\n";
    print "                    -noload          # do ot load paths into databases\n";
}

# date
die "Date doesn't have format YYMMDD\n" unless ($date =~ /\d{6}/);
my ($year,$month,$day) = ($date =~ /(\d\d)(\d\d)(\d\d)/);
my $moredate = "20".$date;
my $fulldate = $day.".".$month.".20".$year;

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
unless (($skip =~ /agp/) || ($skip =~ /qc/) || ($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command; 
        $command = "/software/anacode/bin/oracle2agp -catch_err -species Zebrafish -chromosome $chr -subregion H_".$chr." > $agpdir/chr".$chr.".agp" if ($haplo);
        $command = "/software/anacode/bin/oracle2agp -catch_err -species Zebrafish -chromosome $chr > $agpdir/chr".$chr.".agp" unless ($haplo);
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
    &check_agps unless ($tags);
}
# if agps don't load, identify showstoppers, introduce a gap before or after in tpf (check chromoview to decide where)
# use tpf2oracle -species zebrafish -chr n chrn.tpf to upload, then dump agp again
# alert finishers!


# GET QC CHECKED CLONES
# start here with -skip agp 
unless (($skip =~ /qc/) || ($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    my $command = "/software/zfish/agps/qc_clones.pl > $agpdir/qc_clones.txt";
    &runit($command);
    print "\n" if ($verbose);
}

# CREATE REGION FILES
# start here with -skip qc
unless (($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command = "/software/zfish/agps/make_agps_for_otter_sets.pl -agp $agpdir/chr".$chr.".agp -clones $agpdir/qc_clones.txt";
        $command .= " -haplo" if ($haplo);
        $command .= " > chr".$chr.".region";
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
    
    # create only one agp.new file for chr H
    if ($haplo) {    
        open(OUT,">$agpdir/chrH.region") or die "ERROR: Cannot open $agpdir/chrH.fullagp $!\n";
        foreach my $chr (@chroms) {
            my $line = "N	500000\n";
            my $file = "chr".$chr.".region";
            open(IN,"$agpdir/$file") or die "ERROR: Cannot open $agpdir/$file $!\n";
            while (<IN>) {
                print OUT;
            }
            print OUT $line;
        }
    }
}
#CONVERT REGION FILES TO AGP
# start here with -skip region
unless (($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {
        my $command = "perl /software/anacode/bin/regions_to_agp -chromosome $chr $agpdir/chr".$chr.".region > $agpdir/chr".$chr.".fullagp";
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
}


# GET MISSING CLONE SEQUENCES
unless (($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
	chdir($agpdir);
	my $command1 = "/software/zfish/agps/get_missing_clone_seqs.pl";
	&runit($command1);
}
# stop here if flag 'noload' is chosen.
exit("You chose not to load the agps into the database\n") if ($noload);

# to load directly from agp into new pipedb and loutr db
# perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chrH_20090616 -description chrH_20090616 -host otterpipe2 -user ottadmin -pass wibble -port 3303 -dbname pipe_zebrafish_new ../haplo_agp_090616/chrH.fullagp
# perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chrH_20090616 -description chrH_20090616 -host otterlive -user ottadmin -pass wibble -port 3301 -dbname loutre_zebrafish ../haplo_agp_090616/chrH.fullagp


# LOAD AGPS INTO LOUTRE_ZEBRAFISH AND PIPE_ZEBRAFISH
# start here with -skip newagp
unless (($skip =~ /load/) || ($skip =~ /realign/)) {
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {
#        my $command = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_loutre_pipeline.pl -set chr".$chr."_".$moredate." -description \"chrom ".$chr."\" -dbname loutre_zebrafish $agpdir/chr".$chr.".fullagp";
        my $pipeload  = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chr".$chr."_".$moredate." -description chr".$chr."_".$moredate." -host otterpipe2 -user ottadmin -pass wibble -port 3303 -dbname pipe_zebrafish_new $agpdir/chr".$chr.".fullagp";
        my $otterload = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_from_agp.pl -set chr".$chr."_".$moredate." -description chr".$chr."_".$moredate." -host otterlive -user ottadmin -pass wibble -port 3301 -dbname loutre_zebrafish $agpdir/chr".$chr.".fullagp";
        eval {&runit($pipeload)};
#		eval {&runit($otterload)};
    }
    print "\n" if ($verbose);
}
die "END OF: This is it for haplotype chromosomes, but you might want to set the otter sequence entries and alert anacode to start the analyses\n" if ($haplo);
print STDERR "this is it for the moment, you need to load the assembly tags\n";
print STDERR "perl /software/anacode/otter/otter_production_main/ensembl-otter/scripts/lace/fetch_assembly_tags_for_loutre -dataset zebrafish -verbose -update -misc -atag\n";
print STDERR "make new clone_sets visible by running the following command in loutre\n";
print STDERR "update seq_region_attrib sra, seq_region sr set sra.value = 0 where sra.attrib_type_id = 129 and sra.seq_region_id = sr.seq_region_id and sr.name like \'\%".$date."\';\n";
die("all done");

# REALIGN GENES
# start here with -skip load
#my $command2 = "touch realign_offtrack_genes.out";
#&runit($command2);
#unless ($skip =~ /realign/) {
#    foreach my $chr (@chroms) {
#        my $command = "\n/software/anacode/bin/realign_offtrack_genes -dataset zebrafish -set chr".$chr."_".$moredate." >> & realign_offtrack_genes.out";
#        my $command = "\n/software/anacode/pipeline/ensembl-pipeline/scripts/Finished/assembly/align_by_component_identity.pl -dataset zebrafish -set chr".$chr."_".$moredate." >> & realign_offtrack_genes.out";
#        &runit($command);
#    }
#
#}

# do this
# cd /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/assembly/
#
# foreach i (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 H U)
#   perl align_by_component_identity.pl -host otterlive -port 3301 -user ottroot -pass lutrasuper -dbname loutre_zebrafish \
#   -assembly Otter -altassembly Otter -chromosomes chr${i}_20080117 -altchromosomes chr${i}_20080214 > & /lustre/cbi4/work1/zfish/agps/agp_080214/transfer${i}.log
# end
#
# foreach i (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 H U)
#   perl align_nonident.pl -host otterlive -port 3301 -user ottroot -pass lutrasuper -dbname loutre_zebrafish -assembly Otter -altassembly Otter \
#   -chromosomes chr${i}_20080117 -altchromosomes chr${i}_20080214 > & /lustre/cbi4/work1/zfish/agps/agp_080214/transferb${i}.log
# end



# LOAD ASSEMBLY TAGS
# start here with -skip realign
if ($tags) {
    my $command2 = "perl /nfs/team71/zfish/kj2/new_cvs/ensembl-otter/scripts/lace/fetch_assembly_tags_for_loutre -dataset zebrafish -verbose -update -misc -atag";
    &runit($command2);
}

# make new sets visible
# first check
# select sr.name, sra.attrib_type_id, sra.value from seq_region sr, seq_region_attrib sra where sr.seq_region_id = sra.seq_region_id and sr.name like '%080214';
# update seq_region_attrib sra, seq_region sr set sra.value = 0 where sra.seq_region_id = sr.seq_region_id and sra.attrib_type_id = 129 and sr.name like '%080207';
########################################################

sub runit {
    my $command = shift;
    print $command,"\n" if ($verbose);
    system("$command") and die "ERROR: Cannot execute $command $!\n" unless ($test);
}


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
