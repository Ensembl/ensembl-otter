#!/usr/local/bin/perl -w

# wrapper that loads agps from chromoview, checks them for redundant clones, 
# then against qc checked clones, loads them into otter, loads assembly tags
# and realigns genes...uff
#
# it also does this for haplotypic clones
#
# 17.11.2005 Kerstin Howe (kj2)
#
#
# if you want to delete a sequence_set use
# /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/delete_sequence_set.pl -host otterpipe2 -port 3303 -user ottadmin -pass lutralutra -dbname pipe_zebrafish -delete -set set1 -set set2 etc.
#
# DON'T source ~kj2/source/otterlib.source
# for last step (loading pipeline db) you need to work off the head
# run /software/anacode/bin/setup_anacode_env

use strict;
use Getopt::Long;

my ($date,$test,$verbose,$skip,$haplo,$tags,$help,$stop,$chroms,$path);
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
);

my @chroms = split /,/, $chroms if ($chroms);
$skip = '' unless $skip;

if (($help) || (!$date)){
    print "agp_loader.pl -date YYMMDD\n";
    print "              -skip            # skip steps in order agp, qc, region, fullagp, load\n";
    print "              -haplo           # loads chr H clones\n";
    print "              -chr             # runs for your comma separated list of chromosomes\n";
    print "              -path            # path to build new agp folder in\n";
    print "              -tags            # load assembly tags\n";
    print "              -test            # don't execute system commands\n";
    print "              -verbose         # print commands\n";
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

############
# get agps #
############

unless (($skip =~ /agp/) || ($skip =~ /qc/) || ($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command; 
        $command = "/software/anacode/bin/oracle2agp -species Zebrafish -chromosome $chr -subregion H_".$chr." > $agpdir/chr".$chr.".agp" if ($haplo);
        $command = "/software/anacode/bin/oracle2agp -species Zebrafish -chromosome $chr > $agpdir/chr".$chr.".agp" unless ($haplo);
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
    &check_agps unless ($tags);
}

#################
# get qc clones #
#################

# start here with -skip agp 

unless (($skip =~ /qc/) || ($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    my $command = "/software/zfish/agps/qc_clones.pl > $agpdir/qc_clones.txt";
    &runit($command);
    print "\n" if ($verbose);
}

#######################
# create region files #
#######################

# start here with -skip qc

unless (($skip =~ /region/) || ($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command = "/software/zfish/agps/make_agps_for_otter_sets_new.pl -agp $agpdir/chr".$chr.".agp -clones $agpdir/qc_clones.txt";
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

##########################
# convert regions to agp #
##########################

# start here with -skip region

unless (($skip =~ /newagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {
        my $command = "perl /software/anacode/bin/regions_to_agp -chromosome $chr $agpdir/chr".$chr.".region > $agpdir/chr".$chr.".fullagp";
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
}


######################
# get missing clones #
######################

chdir($agpdir);
my $command1 = "/software/zfish/agps/get_missing_clone_seqs.pl";
&runit($command1);


#############
# load agps #
#############

# start here with -skip newagp

unless (($skip =~ /load/) || ($skip =~ /realign/)) {
    @chroms = ("H") if ($haplo);
# not necessary anymore with new schema
#    foreach my $chr (@chroms) {
#        my $command = "/software/anacode/bin/load_otter_ensembl -no_submit -dataset zebrafish -description \"chromosome_".$chr."_".$fulldate."\" -set chr".$chr."_".$moredate." $agpdir/chr".$chr.".fullagp";
#        &runit($command);
#    }
    print "\n" if ($verbose);
    foreach my $chr (@chroms) {
        my $command = "perl /software/anacode/pipeline/ensembl-pipeline/scripts/Finished/load_loutre_pipeline.pl -set chr".$chr."_".$moredate." -description \"chromosome_".$chr."_".$fulldate."\" -host otterlive -name loutre_zebrafish $agpdir/chr".$chr.".fullagp";
#        my $command = "perl /software/anacode/bin/load_from_otter.pl -chr chr".$chr."_".$moredate." -chromosome_cs_version Otter -o_name otter_zebrafish -host otterpipe2 -port 3303 -name pipe_zebrafish";
#        my $command = "perl /nfs/team71/analysis/ml6/work/pipe_prod/ensembl-pipeline/scripts/Finished/load_from_otter_to_pipeline.pl -chr chr".$chr."_".$moredate." -chromosome_cs_version Otter -o_name otter_zebrafish -p_host otterpipe2 -p_port 3303 -p_name pipe_zebrafish";
        print "$command\n";
    }
    print "\n" if ($verbose);
}
#exit(0) if ($stop);
die "END OF: This is it for haplotype chromosomes, but you might want to set the otter sequence entries and alert anacode to start the analyses\n" if ($haplo);

##########################
# realign offtrack genes #
##########################

# start here with -skip load
my $command2 = "touch realign_offtrack_genes.out";
&runit($command2);

unless ($skip =~ /realign/) {
    foreach my $chr (@chroms) {
        #my $command = "\n/software/anacode/bin/realign_offtrack_genes -dataset zebrafish -set chr".$chr."_".$moredate." >> realign_offtrack_genes.out";
        my $command = "\n/software/anacode/bin/realign_offtrack_genes -dataset zebrafish -set chr".$chr."_".$moredate." >> & realign_offtrack_genes.out";

        # warning: check for latest port by checking for the latest release at /nfs/disk100/humpub
        &runit($command);
    }
}
exit(0) if ($stop);
######################
# load assembly tags #
######################

# start here with -skip realign

if ($tags) {
    my $command2 = "/nfs/team71/zfish/kj2/cvs_bin/ensembl-otter/scripts/lace/fetch_assembly_tags -dataset zebrafish -verbose";
    &runit($command2);
}

############
# and last #
############

print STDERR "DON'T forget to set the otter sequence_set entries, run /nfs/team71/zfish/kj2/cvs_bin/ensembl-otter/scripts/check_genes.pl and alert anacode to start the analyses!\n";
print STDERR "DON'T forget to run \$ANNO/check4newcloneversions.pl\n";


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
            my @a = split /\s+/;
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
    die "ERROR: agps are incorrect\n" if ($alarm > 0);
}
