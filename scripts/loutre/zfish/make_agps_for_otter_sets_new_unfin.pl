#!/usr/local/bin/perl
# 
# filters agps taken from chromoview for qc checked clones
# creates files to build sets for otter 
# this version modified by te3 to permit unfinished clones at line 47
#
# 25.03.04 Kerstin Jekosch <kj2@sanger.ac.uk> 


use strict;
use warnings;

use Getopt::Long;
 
my ($agp,$clones,$help,$haplo);
my $hm = GetOptions(
        'agp:s'     => \$agp,
        'clones:s'  => \$clones,
        'h'         => \$help,
        'haplo'     => \$haplo,
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

    my $gapline  = "N\t10000\n";
    my $clonegap = "N\t5001\n";
    my $haplogap = "N\t500000\n";
    my $lastgap;
    my $started;
    
    while (<AGP>) {
        chomp;
        # clone line
        if (/\tF\t/ or /\tU\t/ or /\tA\t/)  {
            my ($chr,$cstart,$cend,$no,$type,$name,$start,$end,$dir) = split /\t/;
            my $short;
	    
            if ($type eq 'F' and ! exists $qc{$name}) { #only require finished clones to be QC checked

                unless ($lastgap) {
                    ($haplo) ? print $haplogap : print $clonegap;
                    $lastgap++;
                }    
                print STDERR "Taking out $name\n";

	    }
	    else {
                print "$type\t$name\t$start\t$end\t$dir\n";
                $lastgap =0;
            }    
        }
#        elsif (/\tU\t/) {
#        }
#        elsif (/\tA\t/) {    
#        }

        # gap line
        else {
            my ($chr,$cstart,$cend,$no,$type,$gap,$gaptype,$yes) = split /\t/;
            if ($gaptype eq 'clone') {
                unless ($lastgap) {
                    ($haplo) ? print $haplogap : print $clonegap;
                    $lastgap++;
                }
            }
            elsif ($gaptype eq 'contig') {
                unless ($lastgap) {
                    ($haplo) ? print $haplogap : print $gapline;
                    $lastgap++;
                }
            }
            else {
                die "something wrong with line in $agp.agp $1\n";
            }
        }
    }
}

sub help {
    print "USAGE: make_agps_for_otter_sets.pl -agp agpfile -clones qc_checked_clones_file\n";
    exit(0);
}
















