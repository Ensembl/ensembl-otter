#!/usr/local/bin/perl

use strict;
use Getopt::Long;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;


my $s_host    = 'ecs2d';
my $s_user    = 'ensro';
my $s_pass    = '';
my $s_dbname  = 'homo_sapiens_core_12_31';
my $s_port    = 3306;

my $t_host    = 'ecs2c';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 19322;
my $t_dbname  = 'otter_chr7_with_anal';

my $chr      = '7';
my $chrstart = 1;
my $chrend   = 200000000;
my $s_path     = 'NCBI31';
my $t_path     = 'NCBI_31';

&GetOptions( 's_host:s'    => \$s_host,
             's_user:s'    => \$s_user,
             's_pass:s'    => \$s_pass,
             's_port:s'    => \$s_port,
             's_dbname:s'  => \$s_dbname,
             's_path:s'  => \$s_path,
             't_host:s'=> \$t_host,
             't_user:s'=> \$t_user,
             't_pass:s'=> \$t_pass,
             't_port:s'=> \$t_port,
             't_dbname:s'  => \$t_dbname,
             't_path:s'  => \$t_path,
             'chr:s'     => \$chr,
             'chrstart:n'=> \$chrstart,
             'chrend:n'  => \$chrend,
            );



my $sdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $s_host,
					       -user => $s_user,
					       -pass => $s_pass,
					       -port => $s_port,
					       -dbname => $s_dbname);

$sdb->assembly_type($s_path);

my $tdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $t_host,
					       -user => $t_user,
					       -pass => $t_pass,
					       -port => $t_port,
					       -dbname => $t_dbname);

$tdb->assembly_type($t_path);

my $s_sgp = $sdb->get_SliceAdaptor;
my $t_sgp = $tdb->get_SliceAdaptor;
my $t_ga = $tdb->get_GeneAdaptor;
my $t_ta = $tdb->get_TranscriptAdaptor;
my $t_ea = $tdb->get_ExonAdaptor;


my $s_vcontig = $s_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);

my $t_vcontig = $t_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);

my $genes = $s_vcontig->get_all_Genes();

foreach my $gene (@$genes) {
  # $gene->adaptor($t_ga);
  foreach my $tran (@{$gene->get_all_Transcripts}) {
    $tran->sort;

    # These lines force loads from the database to stop attempted lazy 
    # loading during the write (which fail because they are to the wrong
    # db) 

        
    my @exons= @{$tran->get_all_Exons};
    my $get = $tran->translation;
        
    foreach my $exon (@exons) {
      $exon->stable_id;
      $exon->contig($t_vcontig);
    }
   # $tran->adaptor($t_ta);
  }

# Transform gene to raw contig coords
  print "Gene " .$gene->start ." to " . $gene->end  . " type ".$gene->type."\n";
  $gene->transform;

  $t_ga->db->begin_work;
  $t_ga->store($gene);
  $t_ga->db->commit;
}
