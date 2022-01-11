#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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

#
# filters agps taken from chromoview
# (previously, for qc checked clones; now just for gap type+size, and
# negative overlap)
# creates files to build sets for otter
#
# 25.03.04 Kerstin Jekosch <kj2@sanger.ac.uk>


use strict;
use warnings;

use Getopt::Long;

my ($agp,$help,$haplo);
my $exitcode = 0;

my $hm = GetOptions(
        'agp:s'     => \$agp,
        'h'         => \$help,
        'haplo'     => \$haplo,
);

&help if ($help || (!$agp));

# read through agp
if ($agp) {

    open(AGP, '<', $agp) or die "Can't read $agp: $!\n";
#    open(AGPOUT,'>',"./$agp.new") or die "Can't write $agp.new: $!\n";

    my $gapline  = "N\t10000\n";
    my $clonegap = "N\t5001\n";
    my $haplogap = "N\t500000\n";
    my $lastgap;
    my $started;

    while (<AGP>) {
        chomp;
	my @column = split /\t/;

        # clone line
        if ($column[4] eq 'F')  {
            my ($chr,$cstart,$cend,$no,$type,$name,$start,$end,$dir) = @column;

	    if ($end < $start && $cstart == $cend + 1) {
		warn "$chr:$.: Taking out $name (negative overlap) - **temporary fix**\n";
		# Negative overlaps are an artifact of the choice of overlap,
		#
		#	A +++++++++++----
		#	B     ---------------
		#	C         ---++++++++++++
		#
		# Sequence is contributed only by A and C, but because
		# B is part of the tiling path (and for good reason
		# e.g. contains interesting variants) an F-clone line
		# is squeezed in.
		$exitcode |= 16;
	    }
	    else {
                print "F\t$name\t$start\t$end\t$dir\n";
                $lastgap =0;
            }
        }
#        elsif ($column[4] eq 'U') {
#        }
#        elsif ($column[4] eq 'A') {
#        }

        ## changed code slightly to adapt to Will's agp format (br2, 17.05.2010)
	# gap line
        else {
            my ($chr,$cstart,$cend,$no,$type,$gap,$gaptype) = @column;
	    if ($type ne 'N') {
		warn "$chr:$.: Gap, type 'N' expected but got $type\n";
		$exitcode |= 4;
	    }

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
		    warn "something wrong at $agp:$.: $chr,$cstart,$cend,$no,$type,$gap,$gaptype\n";
		    $exitcode |= 2;
                    unless ($lastgap) {
                        ($haplo) ? print $haplogap : print $gapline;
                        $lastgap++;
		    }
                }
            }

        }

        # gap line
#         else {
#           my ($chr,$cstart,$cend,$no,$type,$gap,$gaptype,$yes) = @column;
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
#               warn "something wrong at $agp:$.: $chr,$cstart,$cend,$no,$type,$gap,$gaptype,$yes\n";
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
    print "USAGE: make_agps_for_otter_sets.pl -agp foo.agp > foo.regions\n";
    exit(0);
}


END { $? ||= $exitcode } # declare exit failure, if we are not dying
