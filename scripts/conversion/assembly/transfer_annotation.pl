#!/usr/local/bin/perl

use strict;
use Getopt::Long;

use Bio::Otter::DBSQL::DBAdaptor;


my $host    = '';
my $user    = '';
my $pass    = '';
my $dbname  = '';
my $port;

my $c_host    = '';
my $c_user    = '';
my $c_pass    = '';
my $c_port;
my $c_dbname  = '';

my $t_host    = '';
my $t_user    = '';
my $t_pass    = '';
my $t_port;
my $t_dbname  = '';

my $chr      = '';
my $chrstart = 1;
my $chrend   = 300000000;
my $path     = '';
my $c_path   = '';
my $t_path   = '';

my $filter_gd;
my $filter_obs;
my $filter_anno;
my $gene_type;
my @gene_stable_ids;
my $opt_t;
my $opt_o;

&GetOptions( 'host:s'           => \$host,
             'user:s'           => \$user,
             'pass:s'           => \$pass,
             'port:s'           => \$port,
             'dbname:s'         => \$dbname,
             'c_host:s'         => \$c_host,
             'c_user:s'         => \$c_user,
             'c_pass:s'         => \$c_pass,
             'c_port:s'         => \$c_port,
             'c_dbname:s'       => \$c_dbname,
             't_host:s'         => \$t_host,
             't_user:s'         => \$t_user,
             't_pass:s'         => \$t_pass,
             't_port:s'         => \$t_port,
             't_dbname:s'       => \$t_dbname,
             'chr:s'            => \$chr,
             'chrstart:n'       => \$chrstart,
             'chrend:n'         => \$chrend,
             'path:s'           => \$path,
             'c_path:s'         => \$c_path,
             't_path:s'         => \$t_path,
	     'filter_gd'        => \$filter_gd,
	     'filter_obs'       => \$filter_obs,
	     'gene_type:s'      => \$gene_type,
	     'gene_stable_id:s' => \@gene_stable_ids,
	     't'                => \$opt_t,
	     'o:s'              => \$opt_o,
             'filter_annotation'=> \$filter_anno,
            );

my %gene_stable_ids;
if (scalar(@gene_stable_ids)) {
  my $gene_stable_id=$gene_stable_ids[0];
  if(scalar(@gene_stable_ids)==1 && -e $gene_stable_id){
    # 'gene' is a file
    @gene_stable_ids=();
    open(IN,$gene_stable_id) || die "cannot open $gene_stable_id";
    while(<IN>){
      chomp;
      push(@gene_stable_ids,$_);
    }
    close(IN);
  }else{
    @gene_stable_ids = split (/,/, join (',', @gene_stable_ids));
  }
  print "Using list of ".scalar(@gene_stable_ids)." gene stable ids\n";
  %gene_stable_ids = map {$_,1} @gene_stable_ids;
}

my $sdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $host,
                                           -user => $user,
                                           -pass => $pass,
                                           -port => $port,
                                           -dbname => $dbname);

$sdb->assembly_type($path);

my $cdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $c_host,
                                             -user => $c_user,
                                             -pass => $c_pass,
                                             -port => $c_port,
                                             -dbname => $c_dbname);

$cdb->assembly_type($c_path);

my $tdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $t_host,
                                             -user => $t_user,
                                             -pass => $t_pass,
                                             -port => $t_port,
                                             -dbname => $t_dbname);

$tdb->assembly_type($t_path);

my $sgp = $sdb->get_SliceAdaptor;
my $aga = $sdb->get_GeneAdaptor;
my $sfa = $sdb->get_SimpleFeatureAdaptor;
my $exa = $sdb->get_ExonAdaptor;

my $c_sgp = $cdb->get_SliceAdaptor;
my $c_aga = $cdb->get_GeneAdaptor;
my $c_sfa = $cdb->get_SimpleFeatureAdaptor;

my $t_sgp = $tdb->get_SliceAdaptor;
my $t_aga = $tdb->get_GeneAdaptor;
my $t_sfa = $tdb->get_SimpleFeatureAdaptor;

my $vcontig = $sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);
print "Fetched slice\n";

my $c_vcontig = $c_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);
print "Fetched comparison slice\n";

my $t_vcontig = $t_sgp->fetch_by_chr_start_end($chr,$chrstart,$chrend);
print "Fetched target vcontig\n";

my $genes = $aga->fetch_by_Slice($vcontig);
print "Fetched ".scalar(@$genes)." genes\n";


# find genes that have at least one exon in a clone with the remark 'annotated'
my %okay_genes;
my %parentclone;
my $okaycount;
if ($filter_anno) {
    my $sthx = $sdb->prepare(q{
         select distinct gsi.stable_id, cl.name from 
         gene g, gene_stable_id gsi, transcript t, exon_transcript et, exon e, contig c, clone cl, clone_info ci, clone_remark cr 
         where gsi.gene_id = g.gene_id 
         and g.gene_id = t.gene_id 
         and t.transcript_id = et.transcript_id 
         and et.exon_id = e.exon_id 
         and e.contig_id = c.contig_id 
         and c.clone_id = cl.clone_id 
         and cl.clone_id = ci.clone_id 
         and ci.clone_info_id = cr.clone_info_id 
         and cr.remark like '%annotated%';
    });
    $sthx->execute();
    while (my @row = $sthx->fetchrow_array) {
        $okay_genes{$row[0]}++;
        $parentclone{$row[0]} = $row[1];
        $okaycount++;
    }
}
print "$okaycount genes were marked as annotated\n";


# get the genes
my %genehash;
my $ngd=0;
my $nobs=0;
my $nskipped=0;
my $not_okay=0;
open(OUT,">$opt_o") || die "cannot open $opt_o" if $opt_o;
foreach my $gene (@$genes) {
    my $gsi=$gene->stable_id;
    my $version=$gene->version;
    if(scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }
    if($filter_gd){
	my $name=$gene->gene_info->name->name;
	if($name=~/\.GD$/ || $name=~/^GD:/){
	    print "GD gene $gsi $name was ignored\n";
	    $ngd++;
	    next;
	}
    }
    my $type=$gene->type;
    if($filter_obs){
	if($type eq 'obsolete'){
	    print "Gene $gsi is type obsolete\n";
	    $nobs++;
	    next;
	}
    }
    if($gene_type){
      if($type ne $gene_type){
	print "Gene $gsi skipped - not of type $gene_type\n";
	$nskipped++;
	next;
      }
    }
    
    
    # filter out genes that don't have at least one exon in a clone marked as 'annotated'
    if ($filter_anno) {
        if (exists $okay_genes{$gsi}) {
            print "Gene $gsi is fine and will be taken\n";
        }
        else {
            if ($parentclone{$gsi}) {
                print "Gene $gsi from clone(s) ",$parentclone{$gsi}," is not in clone marked as 'annotated' - skipping\n";
            }
            else {
                print "Gene $gsi is not in clone marked as 'annotated' - skipping\n";
            }
            $not_okay++;            
            next;
        }
    }
    
    
    
    $genehash{$gsi} = $gene;
    print OUT "$gsi\t$version\n" if $opt_o;
}
close(OUT) if $opt_o;
print "$ngd GD genes removed, $nobs obsolete genes removed, $nskipped skipped as incorrect type, $not_okay skipped as not in annotated part\n";
print scalar(keys %genehash)." genes to transfer\n";

exit 0 if $opt_t;




my $c_genes = $c_aga->fetch_by_Slice($c_vcontig);
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
      print "Ignoring gene " . $c_gene->stable_id . " which is on multiple sequences\n";
      $nignored++;
      next CGENE;
    }
  }
# Is it at all mapped
  if ($firstseqname ne $c_vcontig->name) {
    print "Ignoring gene " . $c_gene->stable_id . " which is completely off path on $firstseqname\n";
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
#          if (scalar(@{$exons[$i]->get_all_supporting_features}) != 
#              scalar(@{$c_exons[$i]->get_all_supporting_features})) {
#            print "Exon support different for " . $exons[$i]->stable_id . " and " . 
#                  $c_exons[$i]->stable_id . " in transcript " . $c_tran->stable_id . "\n";
#            $isdiff=1;
#          }
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
  } else {
    eval {
      write_gene($t_aga,$t_vcontig,$c_gene);
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
  my ($t_aga,$t_vcontig,$gene) = @_;

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
      $exon->get_all_supporting_features; 
    }
  }

# Transform gene to raw contig coords
  print "Gene " .$gene->start ." to " . $gene->end  . " type ".$gene->type."\n";
  $gene->transform;

  $t_aga->store($gene);
}

