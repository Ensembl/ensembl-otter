#!/usr/local/perl/bin -w
# Author: Kerstin Jekosch
# Email: kj2@sanger.ac.uk

# transfers the remark 'annotated' from otter_zebrafish to the vega database 
# use like
# transfer_clone_remark.pl -dbname zfish_vega_0904 -dbhost ecs4 -dbport 3352 -dbuser ensadmin -dbpass ensembl -otname otter_zebrafish -othost humsrv1 -otuser ensro


use strict;
use Carp;
use Getopt::Long;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::Lace::Defaults;
use Data::Dumper;
use Bio::Otter::DBSQL::DBAdaptor;

my ($dbhost,$dbuser,$dbname,$dbpass,$dbport);
my ($othost,$otuser,$otname,$otpass,$otport);
my $hm = GetOptions(
        'dbhost:s' => \$dbhost,
        'dbname:s' => \$dbname,
        'dbuser:s' => \$dbuser,
        'dbpass:s' => \$dbpass,
        'dbport:s' => \$dbport,
        'othost:s' => \$othost,
        'otname:s' => \$otname,
        'otuser:s' => \$otuser,
        'otpass:s' => \$otpass,
        'otport:s' => \$otport,
);

my $db = Bio::Otter::DBSQL::DBAdaptor->new(
    -host   => $dbhost,
    -dbname => $dbname,
    -user   => $dbuser,
    -pass   => $dbpass,
    -port   => $dbport,
);

my $otdb = Bio::Otter::DBSQL::DBAdaptor->new(
    -host   => $othost,
    -dbname => $otname,
    -user   => $otuser,
    -pass   => $otpass,
    -port   => $otport,
);

my %vers;
my $sth1 = $otdb->prepare(q{
    select distinct c.embl_acc, c.embl_version, cr.remark 
    from clone_remark cr, current_clone_info ci, clone c  
    where cr.clone_info_id = ci.clone_info_id 
    and c.clone_id = ci.clone_id 
    and cr.remark rlike '^Annotation_remark-[[:blank:]]*annotated'
});

$sth1->execute();
while (my @row = $sth1->fetchrow_array) {
  if($row[2]=~/^Annotation_remark-\s+(annotated\S*)/){
    $vers{$row[0]}->{$row[1]}=$1;
  }
}

my $clone_aptr     = $db->get_CloneAdaptor;
my $clinfo_adaptor = $db->get_CloneInfoAdaptor;
my $author         = Bio::Otter::Author->new(
    -NAME  => 'zfish-help',
    -EMAIL => 'zfish-help@sanger.ac.uk',);
     

CLONE:foreach my $acc (keys %vers) {
    VERS:foreach my $vers (keys %{$vers{$acc}}) {
	# capture label (allows 'annotated' and 'annotated_PREFIX:' to be supported)
        my $annotated_label=$vers{$acc}->{$vers};
        my $clone;
        eval {
            $clone = $clone_aptr->fetch_by_accession_version($acc,$vers);
        };
        if ($@) {
            warn "$acc\.$vers is not present in current vega\n";
            next VERS;
        }
        my $info = $clone->clone_info;
        
        my $new = Bio::Otter::CloneInfo->new(
            -CLONE_ID => $clone->dbID,
            -KEYWORD  => [$info->keyword],
            -AUTHOR => $author,);
	# BUG - I don't think the following works as expected
	# remarks are added, not overwritten it seems
        foreach my $rem ($info->remark) {
            unless ($rem->remark =~ /^Annotation_remark-/) {
                $new->remark($rem);
            }
        }
#        foreach my $kw ($info->keyword) {
#            print "$acc.$vers\t",$kw->name,"\n";
#        }    
        
#        print "have ",scalar ($new->remark) ," remarks\n";
        my $newremark = Bio::Otter::CloneRemark->new(
            -REMARK => "Annotation_remark- $annotated_label",);
        $new->remark($newremark);
#        print "now have ",scalar ($new->remark) ," remarks\n";

#        unless ($info->clone_id){
#            print "$acc.$vers doesn't come with clone_info\n"; 
#        }
        $clinfo_adaptor->store($new);
        
        # test
#        my $num;
#        foreach my $rem ($new->remark) {
#            $num++; 
#            print "$acc.$vers\t",$new->clone_id,"\t",$rem->remark,"\n";
#            print "$num\t$acc.$vers\n";
#        }    
    }
}

#######################################################################

sub help {
    print STDERR "USAGE: \n";
}
