#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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

# Author: Kerstin Jekosch
# Email: kj2@sanger.ac.uk

use strict;
use warnings;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport);
my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
);


$dbhost = 'ecs4';
$dbuser = 'ensro';
$dbport = 3352;
$dbname = 'zebrafish_finished';

my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport,
)
;

&help unless ($dbhost && $dbuser && $dbname);




#clones
my $sth = $db->prepare(q{
    select name, embl_acc, count(distinct embl_version)  as versions 
    from clone 
    group by embl_acc having versions > 1
});

$sth->execute();

my %clone;
while (my @row = $sth->fetchrow_array) {
    my ($name,$acc,$count) = @row;
    $clone{$acc}++;
}    

# end

my $sth1 = $db->prepare(q{
    select c.contig_id, c.name, a.type from contig c, clone cl, assembly a where cl.embl_acc = ? and c.clone_id = cl.clone_id and c.contig_id = a.contig_id
});
foreach my $acc (keys %clone) {
    $sth1->execute($acc);
    while (my @row = $sth1->fetchrow_array) {
        print join "\t", @row,"\n";
 
    }
}


#######################################################################

sub help {
    print STDERR "USAGE: \n";
}

