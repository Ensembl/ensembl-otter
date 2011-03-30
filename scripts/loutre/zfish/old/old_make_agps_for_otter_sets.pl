#!/usr/local/bin/perl -w
# 
# filters agps taken from chromoview for qc checked clones
# creates files to build sets for otter 
#
# 25.03.04 Kerstin Jekosch <kj2@sanger.ac.uk> 


use strict;
use Getopt::Long;
 
my ($agp,$clones,$help);
my $hm = GetOptions(
        'agp:s'     => \$agp,
        'clones:s'  => \$clones,
        'h'         => \$help,
);

&help if ($help || (!$agp) || (!$clones)); 

# get names of qc checked clones
open(CL,$clones) or die "Can't open $clones\n";
my %qc;
while (<CL>) {
    /\S+\s+(\S+)\s+(\d+)\s+\d+/ and do {
        $qc{$1.".".$2}++;
    };
}

# read through agp
if ($agp) {

    open(AGP,$agp) or die "Can't open $agp\n";
#    open(AGPOUT,">./$agp.new") or die "Can't open $agp.new\n";

    my $gapline  = "N\t5000\n";
    my $clonegap = "N\t1000\n";
    my $lastgap;
    my $started;
    
    while (<AGP>) {
        chomp;
        # clone line
        if (/\tF\t/) {
            $started = 1;
            my ($chr,$cstart,$cend,$no,$type,$name,$start,$end,$dir) = split /\t/;
            my $short;

            if (exists $qc{$name}) {
                print "F\t$name\t$start\t$end\t$dir\n";
                $lastgap = 0;
            }    

            else {
                print $gapline unless (($lastgap) && ($lastgap == 1));
                print $clonegap;
                print STDERR "Taking out $name\n";
            }
        }

        # gap line
        else {
            if ($started) {
                print $gapline unless ($lastgap == 1);
                $lastgap = 1;
            }
        }
    }
}

sub help {
    print "USAGE: make_agps_for_otter_sets.pl -agp agpfile -clones qc_checked_clones_file\n";
    exit(0);
}
















