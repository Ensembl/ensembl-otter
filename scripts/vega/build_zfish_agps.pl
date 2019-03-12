#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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


# wrapper that loads agps from chromoview, checks them for redundant clones, 
# then against qc checked clones, loads them into otter, loads assembly tags
# and realigns genes...uff
#
# it also does this for haplotypic clones
#
# 17.11.2005 Kerstin Howe (kj2)

use strict;
use warnings;

use Getopt::Long;

my ($date,$test,$verbose,$skip,$haplo,$tags,$help,$stop,$chroms,$path);
GetOptions(
        'date:s'   => \$date,       # format YYMMDD 
        'test'     => \$test,       # doesn't execute system commands
        'verbose'  => \$verbose,    # prints all commands 
        'skip:s'   => \$skip,       # skips certain steps
        'tags'     => \$tags,       # loads assembly tags
        'h'        => \$help,       # help
        'stop'     => \$stop,       # stops where you've put yuor exit(0) if ($stop)
        'haplo'    => \$haplo,      # deals with chr H clones (only)
        'chr:s'    => \$chroms,     # overrides all chromosomes
        'path:s'   => \$path,       # overrides /nfs/disk100/zfishpub/annotation/ana_notes_update
);

my @chroms = split /,/, $chroms if ($chroms);

if (($help) || (!$date)){
    print "build_zfish_agps.pl.pl -date YYMMDD\n";
    print "                       -skip            # skip steps in order agp, qc, region, fullagp, load, realign\n";
    print "                       -haplo           # loads chr H clones\n";
    print "                       -chr             # runs for your comma separated list of chromosomes\n";
    print "                       -path            # path to build new agp folder in\n";
    print "                       -tags            # load assembly tags\n";
    print "                       -test            # don't execute system commands\n";
    print "                       -verbose         # print commands\n";
}

# date
die "Date doesn't have format YYMMDD\n" unless ($date =~ /\d{6}/);
my ($year,$month,$day) = ($date =~ /(\d\d)(\d\d)(\d\d)/);
my $moredate = "20".$date;
my $fulldate = $day.".".$month.".20".$year;

# paths
$path = "/nfs/disk100/zfishpub/annotation/ana_notes_update" unless ($path);
my $agp = "agp_".$date;
my $agpdir; 
$agpdir = $path."/".$agp       unless ($haplo);
$agpdir = $path."/haplo_".$agp if ($haplo);
@chroms = (1..25,"U") unless (@chroms);

print "Making $agpdir\n" unless (($test) || ($skip =~ /\S+/));
mkdir($agpdir,0777) or die "ERROR: Cannot make agp_$date $!\n" unless (($test) || ($skip =~ /\S+/));
chdir($agpdir);

############
# get agps #
############

unless (($skip =~ /agp/) || ($skip =~ /qc/) || ($skip =~ /region/) || ($skip =~ /fullagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command; 
        $command = "perl /nfs/team71/zfish/kj2/cvs_bin/fish/chromoview/oracle2agp -species Zebrafish -chromosome $chr -subregion H_".$chr." > $agpdir/chr".$chr.".agp" if ($haplo);
        $command = "perl /nfs/team71/zfish/kj2/cvs_bin/fish/chromoview/oracle2agp -species Zebrafish -chromosome $chr > $agpdir/chr".$chr.".agp" unless ($haplo);
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
    &check_agps;
}

#################
# get qc clones #
#################

# start here with -skip agp 

unless (($skip =~ /qc/) || ($skip =~ /region/) || ($skip =~ /fullagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    my $command = "$path/qc_clones.pl > $agpdir/qc_clones.txt";
    &runit($command);
    print "\n" if ($verbose);
}

#######################
# create region files #
#######################

# start here with -skip qc

unless (($skip =~ /region/) || ($skip =~ /fullagp/) || ($skip =~ /load/) || ($skip =~ /realign/)) {
    foreach my $chr (@chroms) {
        my $command = "$path/make_agps_for_otter_sets.pl -agp $agpdir/chr".$chr.".agp -clones $agpdir/qc_clones.txt > chr".$chr.".agp.new";
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
    
    # create only one agp.new file for chr H
    if ($haplo) {
        open(OUT,">$agpdir/chrH.agp.new") or die "ERROR: Cannot open $agpdir/chrH.fullagp $!\n";
        foreach my $chr (@chroms) {
            my $line = "N	10000\n";
            my $file = "chr".$chr.".agp.new";
            open(IN,"$agpdir/$file") or die "ERROR: Cannot open $agpdir/$file $!\n";
            while (<IN>) {
                print OUT;
            }
            print OUT $line;
        }
    }
}
exit(0) if ($stop);

##########################
# convert regions to agp #
##########################

# start here with -skip region

unless (($skip =~ /fullagp/) || ($skip =~ /load/) || ($skip =~ /realign/)){
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {
        my $command = "perl /nfs/team71/zfish/kj2/cvs_bin/fish/chromoview/regions_to_agp -chromosome $chr $agpdir/chr".$chr.".agp.new > $agpdir/chr".$chr.".fullagp";
        eval {&runit($command)};
    }
    print "\n" if ($verbose);
}

#############
# load agps #
#############

# start here with -skip newagp

unless (($skip =~ /load/) || ($skip =~ /realign/)) {
    @chroms = ("H") if ($haplo);
    foreach my $chr (@chroms) {
        my $command = "/nfs/team71/zfish/kj2/cvs_bin/ensembl-otter/scripts/lace/load_otter_ensembl -no_submit -dataset zebrafish -description \"chromosome $chr $fulldate\" -set chr".$chr."_".$moredate." $agpdir/chr".$chr.".fullagp";
        &runit($command);
    }
    print "\n" if ($verbose);
    foreach my $chr (@chroms) {
        my $command = "ATTENTION: You have to run the following under head\nperl /nfs/farm/Fish/kj2/head/ensembl-pipeline/scripts/Finished/load_from_otter_to_pipeline.pl -chr chr".$chr."_".$moredate." -chromosome_cs_version Otter -oname otter_zebrafish -phost otterpipe2 -pport 3323 -pname pipe_zebrafish $agpdir/chr".$chr.".fullagp\n";
        print "$command\n";
    }
    print "\n" if ($verbose);
}
die "END OF: This is it for haplotype chromosomes, but you might want to set the otter sequence entries and alert anacode to start the analyses\n" if ($haplo);

##########################
# realign offtrack genes #
##########################

# start here with -skip load

unless ($skip =~ /realign/) {
    foreach my $chr (@chroms) {
        my $command = "/nfs/team71/zfish/kj2/cvs_bin/ensembl-otter/scripts/lace/realign_offtrack_genes -dataset zebrafish -set chr".$chr."_".$moredate;
        &runit($command);
    }
}

######################
# load assembly tags #
######################

# start here with -skip realign

if ($tags) {
    my $command2 = "/nfs/team71/zfish/kj2/cvs_bin/ensembl-otter/scripts/lace/fetch_assembly_tags -dataset zebrafish -verbose -set all";
    &runit($command2);
}

############
# and last #
############

print STDERR "ATTENTION: Don't forget to set the otter sequence_set entries, run /nfs/team71/zfish/kj2/cvs_bin/ensembl-otter/scripts/check_genes.pl and alert anacode to start the analyses!\n";



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
