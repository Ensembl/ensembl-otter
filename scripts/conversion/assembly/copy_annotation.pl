#!/usr/local/bin/perl

use strict;
use Getopt::Long;

use Bio::Otter::DBSQL::DBAdaptor;


my $s_host    = 'ecs1d';
my $s_user    = 'ensro';
my $s_pass    = '';
my $s_dbname  = 'otter_chr20_with_anal';
my $s_port    = 19322;

my $t_host    = 'ecs1d';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 19322;
my $t_dbname  = 'otter_merged_chrs_with_anal';

my $chr      = '20';
my $chrstart = 1;
my $chrend   = 100000000;
my $path     = 'SANGER';
my $do_clones = 0;

&GetOptions( 's_host:s'    => \$s_host,
             's_user:s'    => \$s_user,
             's_pass:s'    => \$s_pass,
             's_port:s'    => \$s_port,
             's_dbname:s'  => \$s_dbname,
             't_host:s'    => \$t_host,
             't_user:s'    => \$t_user,
             't_pass:s'    => \$t_pass,
             't_port:s'    => \$t_port,
             't_dbname:s'  => \$t_dbname,
             'chr:s'       => \$chr,
             'chrstart:n'  => \$chrstart,
             'chrend:n'    => \$chrend,
             'path:s'      => \$path,
             'clones'      => \$do_clones,
            );



my $sdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $s_host,
                                           -user => $s_user,
                                           -pass => $s_pass,
                                           -port => $s_port,
                                           -dbname => $s_dbname);

$sdb->assembly_type($path);

my $tdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $t_host,
                                             -user => $t_user,
                                             -pass => $t_pass,
                                             -port => $t_port,
                                             -dbname => $t_dbname);

$tdb->assembly_type($path);

my $s_sgp = $sdb->get_SliceAdaptor;
my $s_aga = $sdb->get_AnnotatedGeneAdaptor;
my $s_aca = $sdb->get_AnnotatedCloneAdaptor;

my $t_sgp = $tdb->get_SliceAdaptor;
my $t_aga = $tdb->get_AnnotatedGeneAdaptor;
my $t_aca = $tdb->get_AnnotatedCloneAdaptor;
my $t_ea  = $tdb->get_ExonAdaptor;


my $s_vcontig = $s_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);

my $t_vcontig = $t_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);

my $genes = $s_aga->fetch_by_Slice($s_vcontig);

foreach my $gene (@$genes) {
  foreach my $tran (@{$gene->get_all_Transcripts}) {
    $tran->sort;

    print "Transcript " . $tran->stable_id . "\n";

    # These lines force loads from the database to stop attempted lazy 
    # loading during the write (which fail because they are to the wrong
    # db) 

        
    my @exons= @{$tran->get_all_Exons};
    my $get = $tran->translation;
    $tran->_translation_id(undef);
        
    foreach my $exon (@exons) {
      $exon->stable_id;
      $exon->contig($t_vcontig);
    }
  }

# Transform gene to raw contig coords
  print "Gene " .$gene->start ." to " . $gene->end  . " type ".$gene->type."\n";
  $gene->transform;

  $t_aga->store($gene);
}

if ($do_clones) {
  my $clones = $s_aca->fetch_by_Slice($s_vcontig);
  
  foreach my $clone (@$clones) {
    $t_aca->store($clone);
  }
}
