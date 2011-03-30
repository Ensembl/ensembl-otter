#!/usr/local/perl/bin -w
# Author: Kerstin Jekosch
# Email: kj2@sanger.ac.uk

use strict;
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

