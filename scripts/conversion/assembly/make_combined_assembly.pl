#!/usr/local/bin/perl

use strict;
use Getopt::Long;

use Bio::EnsEMBL::DBSQL::DBAdaptor;


my $host    = 'ecs1d';
my $user    = 'ensadmin';
my $pass    = 'ensembl';
my $port    = 19322;
my $dbname  = 'otter_merged_chrs_with_anal';

my @s_paths;
my $t_path  = 'VEGA';

&GetOptions( 'host:s'=> \$host,
             'user:s'=> \$user,
             'pass:s'=> \$pass,
             'port:s'=> \$port,
             'dbname:s'  => \$dbname,
             't_path:s'  => \$t_path,
             's_path:s'  => \@s_paths,
            );



my $tdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $host,
					       -user => $user,
					       -pass => $pass,
					       -port => $port,
					       -dbname => $dbname);

my $spath_str = "\"" . join ("\",\"",@s_paths) . "\"";

my $sth = $tdb->prepare(qq {
  select chromosome_id,
         chr_start,
         chr_end,
         superctg_name,
         superctg_start,
         superctg_end,
         superctg_ori,
         contig_id,
         contig_start,
         contig_end,
         contig_ori,
         type 
  from assembly
  where assembly.type in ($spath_str)
});
        
$sth->execute;

my $hashref;
while ($hashref = $sth->fetchrow_hashref()) {

  my $sth2 = $tdb->prepare( qq:
    insert into assembly(chromosome_id,
                         chr_start,
                         chr_end,
                         superctg_name,
                         superctg_start,
                         superctg_end,
                         superctg_ori,
                         contig_id,
                         contig_start,
                         contig_end,
                         contig_ori,
                         type) 
                 values( 
                     $hashref->{chromosome_id},
                     $hashref->{chr_start},
                     $hashref->{chr_end},
                     "$hashref->{superctg_name}",
                     $hashref->{superctg_start},
                     $hashref->{superctg_end},
                     $hashref->{superctg_ori},
                     $hashref->{contig_id},
                     $hashref->{contig_start},
                     $hashref->{contig_end},
                     $hashref->{contig_ori},
                     "$t_path"
                   ):);
  $sth2->execute;
}
