#!/usr/local/bin/perl

use strict;
use Getopt::Long;

use Bio::EnsEMBL::DBSQL::DBAdaptor;


my $host    = 'ecs2a';
my $user    = 'ensro';
my $pass    = '';
my $dbname  = 'steve_otter_merged_chrs';
my $port    = 3306;

my $c_host    = 'ecs2a';
my $c_user    = 'ensro';
my $c_pass    = '';
my $c_port    = 3306;
my $c_dbname  = 'steve_otter_merged_chrs';

my $t_host    = 'ecs2a';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 3306;
my $t_dbname  = 'steve_ensembl_vega_ncbi31_2';

my $chr      = '14';
my $chrstart = 1;
my $chrend   = 300000000;
my $path     = 'GENOSCOPE';
my $c_path   = 'NCBI31';
my $t_path   = 'NCBI31';
my $no_offset;

&GetOptions( 'host:s'    => \$host,
             'user:s'    => \$user,
             'pass:s'    => \$pass,
             'port:s'    => \$port,
             'dbname:s'  => \$dbname,
             'c_host:s'    => \$c_host,
             'c_user:s'    => \$c_user,
             'c_pass:s'    => \$c_pass,
             'c_port:s'    => \$c_port,
             'c_dbname:s'  => \$c_dbname,
             't_host:s'    => \$t_host,
             't_user:s'    => \$t_user,
             't_pass:s'    => \$t_pass,
             't_port:s'    => \$t_port,
             't_dbname:s'  => \$t_dbname,
             'chr:s'       => \$chr,
             'chrstart:n'  => \$chrstart,
             'chrend:n'    => \$chrend,
             'path:s'      => \$path,
             'c_path:s'    => \$c_path,
             't_path:s'    => \$t_path,
	     'no_offset'   => \$no_offset,
            );



my $sdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $host,
                                           -user => $user,
                                           -pass => $pass,
                                           -port => $port,
                                           -dbname => $dbname);

$sdb->assembly_type($path);

my $cdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $c_host,
                                             -user => $c_user,
                                             -pass => $c_pass,
                                             -port => $c_port,
                                             -dbname => $c_dbname);

$cdb->assembly_type($c_path);

my $tdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $t_host,
                                             -user => $t_user,
                                             -pass => $t_pass,
                                             -port => $t_port,
                                             -dbname => $t_dbname);

$tdb->assembly_type($t_path);

my $sgp = $sdb->get_SliceAdaptor;
my $aga = $sdb->get_GeneAdaptor;
my $pfa = $sdb->get_ProteinFeatureAdaptor;

my $c_sgp = $cdb->get_SliceAdaptor;
my $c_aga = $cdb->get_GeneAdaptor;

my $t_sgp = $tdb->get_SliceAdaptor;
my $t_aga = $tdb->get_GeneAdaptor;
my $t_pfa = $tdb->get_ProteinFeatureAdaptor;


my $vcontig = $sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);
print "Fetched slice for $chr\n";

my $c_vcontig = $c_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);
print "Fetched comparison slice\n";

my $t_vcontig = $t_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);
print "Fetched target vcontig\n";

my $genes = $vcontig->get_all_Genes();
print "Fetched genes\n";

my %genehash;
foreach my $gene (@$genes) {
  $genehash{$gene->stable_id} = $gene;
}

my $c_genes = $c_vcontig->get_all_Genes();
print "Fetched comparison genes\n";


print "Comparing and writing ....\n";
my $nignored = 0;
my $ncgene = 0;
my $ndiffgene = 0;
CGENE: foreach my $c_gene (@$c_genes) {

  $ncgene++;

  my $isdiff=0;

# Is it fully mapped?
  my @exons =  @{$c_gene->get_all_Exons};
  my $firstseqname = $exons[0]->seqname;
  foreach my $exon (@exons) {
    #print "Exon name " . $exon->seqname . " first seqname " . $firstseqname . "\n";
    if ($exon->seqname ne $firstseqname) {
      print "Ignoring gene " . $c_gene->stable_id . " which is on multiple sequences - not transferred\n";
      $nignored++;
      next CGENE;
    }
  }
# Is it at all mapped
  if ($firstseqname ne $c_vcontig->name) {
    print "Ignoring gene " . $c_gene->stable_id . " which is completely off path on $firstseqname - not transferred\n";
    $nignored++;
    next CGENE;
  }


  if (exists($genehash{$c_gene->stable_id})) {
    my $gene = $genehash{$c_gene->stable_id};

# First check we have the same number of transcripts    
    my @transcripts = @{$gene->get_all_Transcripts};
    my @c_transcripts = @{$c_gene->get_all_Transcripts};

    if (scalar(@c_transcripts) != scalar(@transcripts)) {
      print "Gene " . $gene->stable_id . " has different numbers of transcripts\n";
      $isdiff=1;
    }

    my %tranhash;
    foreach my $tran (@transcripts) {
      $tran->sort;
      $tranhash{$tran->stable_id} = $tran;
    }

    if ($gene->strand != $c_gene->strand) {
      print " Note gene $gene->stable_id on different strands in two assemblies\n";
    }

    foreach my $c_tran (@c_transcripts) {
      $c_tran->sort;

      if (exists($tranhash{$c_tran->stable_id})) {
        my $tran = $tranhash{$c_tran->stable_id};
        my @exons= @{$tran->get_all_Exons};
        my @c_exons= @{$c_tran->get_all_Exons};
            
        if (scalar(@exons) != scalar(@c_exons)) {
          print "Different numbers of exons in transcript " . $c_tran->stable_id . "\n";
          $isdiff=1;
        }

        my $nexon_to_comp = (scalar(@exons) > scalar(@c_exons)) ? scalar(@c_exons) : scalar(@exons);
        my $c_intron_len = 0;
        my $intron_len = 0;


        for (my $i=0;$i<$nexon_to_comp;$i++) {
          if ($exons[$i]->stable_id ne $c_exons[$i]->stable_id) {
            print "Exon stable ids different for " . $exons[$i]->stable_id . " and " . 
                  $c_exons[$i]->stable_id . " in transcript " . $c_tran->stable_id . "\n";
            $isdiff=1;
          }
          if ($exons[$i]->length != $c_exons[$i]->length) {
            print "Exon lengths different for " . $exons[$i]->stable_id . " and " . 
                  $c_exons[$i]->stable_id . " in transcript " . $c_tran->stable_id . "\n";
            $isdiff=1;
          }
          if ($exons[$i]->seq->seq ne $c_exons[$i]->seq->seq) {
            print "Exon sequences different for " . $exons[$i]->stable_id . " and " . 
                  $c_exons[$i]->stable_id . " in transcript " . $c_tran->stable_id . "\n";
            $isdiff=1;
          }
          if ($i != 0) {
            if ($gene->strand == 1) {
              $intron_len   = $exons[$i]->start - $exons[$i-1]->end - 1;
            } else {
              $intron_len   = $exons[$i-1]->start - $exons[$i]->end - 1;
            }

            if ($c_gene->strand == 1) {
              $c_intron_len = $c_exons[$i]->start - $c_exons[$i-1]->end - 1;
            } else {
              $c_intron_len = $c_exons[$i-1]->start - $c_exons[$i]->end - 1;
            }
          }
        }
        my $intron_diff_len = abs($c_intron_len - $intron_len);
        if ($intron_diff_len > $c_intron_len/10) {
          print " Total intron length for transcript ".$c_tran->stable_id." changed by more than 10%%\n";
        }
      } else {
        print "Couldn't find transcript " . $c_tran->stable_id . " to compare against\n";
        $isdiff=1;
      }
    }
  } else {
    print "Couldn't find gene " . $c_gene->stable_id . " to compare against\n";
    $isdiff=1;
  }
  if ($isdiff) {
    $ndiffgene++;
    print " Gene " . $c_gene->stable_id . " from " . $c_gene->start . " to " . $c_gene->end . " (old assembly coords) is different - not transferred\n";
  } else {
    eval {
      write_gene($t_aga,$t_vcontig,$c_gene,$pfa,$t_pfa);
    };
    if ($@) {
      print "Failed writing gene " . $c_gene->stable_id . "\n";
      print $@ . "\n";
    }
  }
}
print "N compared  = " . $ncgene . "\n";
print "N ignored   = " . $nignored . "\n";
print "N diff gene = " . $ndiffgene . "\n";
print "Done\n";

sub write_gene {
  my ($t_aga,$t_vcontig,$gene,$s_pfa,$t_pfa) = @_;

  my %s_pfhash;
  foreach my $tran (@{$gene->get_all_Transcripts}) {
    $tran->sort;

    print "Transcript " . $tran->stable_id . "\n";

    # These lines force loads from the database to stop attempted lazy
    # loading during the write (which fail because they are to the wrong
    # db)


    if (defined($tran->translation)) {
      $s_pfhash{$tran->stable_id} = $s_pfa->fetch_by_translation_id($tran->translation->dbID);
    }

    my @exons= @{$tran->get_all_Exons};
    my $get = $tran->translation;
    $tran->_translation_id(undef);

    foreach my $exon (@exons) {
      $exon->stable_id;
      $exon->contig($t_vcontig);
      $exon->get_all_supporting_features; 
    }

  }

  # Transform gene to raw contig coords
  print "Gene " .$gene->start ." to " . $gene->end  . " type ".$gene->type."\n";
  $gene->transform;

  $t_aga->store($gene);

  foreach my $tran (@{$gene->get_all_Transcripts}) {
    if (defined($s_pfhash{$tran->stable_id})) {
      foreach my $pf (@{$s_pfhash{$tran->stable_id}}) {
        $pf->seqname($tran->translation->dbID);
        if (!$pf->score) { $pf->score(0) };
        if (!$pf->percent_id) { $pf->percent_id(0) };
        if (!$pf->p_value) { $pf->p_value(0) };
        $t_pfa->store($pf);
      }
    }
  }
}

