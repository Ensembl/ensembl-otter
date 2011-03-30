#!/usr/local/bin/perl -w
# 
# filters agps taken from chromoview for qc checked clones
# creates files to build sets for otter 
#
# 25.03.04 Kerstin Jekosch <kj2@sanger.ac.uk> 


use strict;
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
        if (/\tF\t/)  {
            my ($chr,$cstart,$cend,$no,$type,$name,$start,$end,$dir) = split /\t/;
            my $short;

            if (exists $qc{$name}) {
                print "F\t$name\t$start\t$end\t$dir\n";
                $lastgap =0;
            }    

            else {
                unless ($lastgap) {
                    ($haplo) ? print $haplogap : print $clonegap;
                    $lastgap++;
                }    
                print STDERR "Taking out $name\n";
            }
        }
#        elsif (/\tU\t/) {
#        }
#        elsif (/\tA\t/) {    
#        }

        ## changed code slightly to adapt to Will's agp format (br2, 17.05.2010) 
	# gap line
        else {
            my ($chr,$cstart,$cend,$no,$type,$gap,$gaptype) = split /\t/;
            if ($gaptype eq 'FPC') {
                unless ($lastgap) {
                    ($haplo) ? print $haplogap : print $gapline;
                    $lastgap++;
                }
            }
	    # match internal clone name (zC153M16 or zC160G15[U])
            elsif ($gaptype =~ /^\w+\d+\w+\d+$/ || $gaptype =~ /^\w+\d+\w+\d+\[[UA]\]$/) {
                unless ($lastgap) {
                    ($haplo) ? print $haplogap : print $clonegap;
                    $lastgap++;
                }
            }
	    else {
		unless ($gaptype =~ /fragment/) {
		    warn "something wrong with line in $agp.agp $1 chr,$cstart,$cend,$no,$type,$gap,$gaptype\n";
                    unless ($lastgap) {
                        ($haplo) ? print $haplogap : print $gapline;
                        $lastgap++;
		    }    
                }
            }

        }
    
        # gap line
#         else {
#           my ($chr,$cstart,$cend,$no,$type,$gap,$gaptype,$yes) = split /\t/;
#           if ($gaptype eq 'clone') {
#             unless ($lastgap) {
#               ($haplo) ? print $haplogap : print $clonegap;
#               $lastgap++;
#             }
#           }
#           elsif ($gaptype eq 'contig') {
#             unless ($lastgap) {
#               ($haplo) ? print $haplogap : print $gapline;
#               $lastgap++;
#             }
#           }
#           else {
#             unless (($gaptype eq 'CENTROMERE') || ($gaptype =~ /No overlap in database/)
#                      || ($gaptype =~ /dovetail/) || ($gaptype =~ /double.*prime join/)) {
#               warn "something wrong with line in $agp.agp $1 chr,$cstart,$cend,$no,$type,$gap,$gaptype,$yes\n";
#               unless ($lastgap) {
#                 ($haplo) ? print $haplogap : print $gapline;
#                 $lastgap++;
#               }
#             }
#           }
#         }
#
    
    }
}

sub help {
    print "USAGE: make_agps_for_otter_sets.pl -agp agpfile -clones qc_checked_clones_file\n";
    exit(0);
}
















