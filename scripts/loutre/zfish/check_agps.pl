#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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


use strict;
use warnings;

use Getopt::Long;

my ($last,$now);
GetOptions(
    'last:s' => \$last,
    'now:s'  => \$now,
    );
    

my (%last, %now);
foreach my $k (1..25,'U') {
    open(COM1,"grep -c 'F' /nfs/disk100/zfishpub/agps/agp_$last/chr$k.agp |");
    while (<COM1>) {
        /(\d+)/ and do {
            $last{$k} = $1;
        };
    }
    open(COM2,"grep -c 'F' /nfs/disk100/zfishpub/agps/agp_$now/chr$k.agp |");
    while (<COM2>) {
        /(\d+)/ and do {
            $now{$k} = $1;
        };
    }
}

foreach my $n (sort {$a <=> $b} keys %last) {
    my $last = $last{$n};
    my $now  = $now{$n};
    print "$n\t$last\t$now\t";
    print "!" if (abs((int($now/$last*100))-100) > 5);
    print "\n";
}

   
