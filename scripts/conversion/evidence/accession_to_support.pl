#!/usr/local/bin/perl

#Fetch slice for whole chromosome
#For each gene
#Fetch
#check for overlap with any exon in transcript
#create a supporting feature
#write


use strict;

use Getopt::Long;

use Bio::Otter::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::RawContig;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Clone;
use Bio::Seq;
use Bio::SeqIO;

my $t_host    = 'ecs1d';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 19322;
my $t_dbname  = 'otter_merged_chrs_with_anal';

my @chr;
my $path     = 'GENOSCOPE';

$|=1;

my @gene_stable_ids;

&GetOptions( 't_host:s'            => \$t_host,
             't_user:s'            => \$t_user,
             't_pass:s'            => \$t_pass,
             't_port:s'            => \$t_port,
             't_dbname:s'          => \$t_dbname,
             'chr:s'               => \@chr,
             'path:s'              => \$path,
	     'gene_stable_id:s'    => \@gene_stable_ids,
            );

if (scalar(@chr)) {
  @chr = split (/,/, join (',', @chr));
}else{
  die "Missing required args\n";
}

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

my $tdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $t_host,
                                           -user => $t_user,
                                           -pass => $t_pass,
                                           -port => $t_port,
                                           -dbname => $t_dbname);


$tdb->assembly_type($path);

foreach my $chr (@chr){

  print "processing chromsome $chr\n";

  my $chr_slice = $tdb->get_SliceAdaptor()->fetch_by_chr_name($chr);
  
  my $ens_genes = $chr_slice->get_all_Genes;

  my $padding = 1000;

  my %analyses;

  foreach my $ens_gene (@$ens_genes) {
    my $gsi=$ens_gene->stable_id;
    if(scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }

    # get corresponding gene on slice
    my $slice_start=$ens_gene->start-$padding;
    my $slice_end=$ens_gene->end+$padding;
    my $gene_slice = $tdb->get_SliceAdaptor()->fetch_by_chr_start_end($chr,$slice_start,$slice_end);
    my $ott_genes = $tdb->get_GeneAdaptor()->fetch_by_Slice($gene_slice);

    my $gene = undef;
    foreach my $ott_gene (@$ott_genes) {
      if ($ott_gene->dbID == $ens_gene->dbID) {
	$gene = $ott_gene;
	last;
      }
    }
    if (!defined($gene)) {
      die "Failed finding gene which should have been there for " 
	  . $ens_gene->stable_id ."\n";
    }
    my $gsi=$gene->stable_id;
    print "Slice for $gsi is ".
	$slice_start.
	"-".
	$slice_end.
	" (".
	$slice_end-$slice_start.
	")\n";

    # don't process slices no list again
    print "Looking for matches to $gsi\n";
    my $has_support = 0;

    my $fps = $gene_slice->get_all_SimilarityFeatures;

    sort {$a->start <=> $b->start} @$fps;

  OUTER:
    foreach my $trans (@{$gene->get_all_Transcripts}) {
      my $evidence = @{$trans->transcript_info->get_all_Evidence};

      foreach my $evi (@$evidence) {
	my $acc = $evi->name;
	$acc =~ s/.*://;
	$acc =~ s/\.[0-9]*$//;
	print " Looking for $acc\n";
	foreach my $fp (@$fps) {
	  my $cmpname = $fp->hseqname;
	  $cmpname =~ s/\.[0-9]*$//;
	  if ($cmpname eq $acc) {
	    foreach my $exon (@{$trans->get_all_Exons}) {
	      if ($exon->overlaps($fp)) {
		print " Got overlapping accession match dbID = " . $fp->dbID. "\n";
		$fp->analysis(get_Analysis_by_type($tdb,$evi->type . "_evidence"));
		$exon->add_supporting_features($fp);
		$has_support = 1;
	      }
	    }
	  }
	}
      }
    }
    $gene->transform;
    if ($has_support) {
      foreach my $trans (@{$gene->get_all_Transcripts}) {
	foreach my $exon (@{$trans->get_all_Exons}) {
	  store_supporting_features($tdb, $exon);
	}
      }
    }
  }
}

#End main
{
  my( %ana );

  sub get_Analysis_by_type {
    my( $dba, $type ) = @_;
    
    unless (exists($ana{$type})) {
      my $logic = $type;
      my $ana_aptr = $dba->get_AnalysisAdaptor;
      ($ana{$type}) = $ana_aptr->fetch_by_logic_name($logic);
      die "Can't get analysis object for logic name '$logic'"
	  unless exists $ana{$type};
    }
    return $ana{$type};
  }
}


# Nasty but there's no way to just add support to an exon through the API
sub store_supporting_features {
  my ($db, $exon) = @_;

  my $sql = "insert into supporting_feature (exon_id, feature_id, feature_type)
             values(?, ?, ?)";

  my $sf_sth = $db->prepare($sql);

  my $dna_adaptor = $db->get_DnaAlignFeatureAdaptor();
  my $pep_adaptor = $db->get_ProteinAlignFeatureAdaptor();
  my $type;

  my @exons = ();
  if($exon->isa('Bio::EnsEMBL::StickyExon')) {
    @exons = @{$exon->get_all_component_Exons};
  } else {
    @exons = ($exon);
  }

  foreach my $e (@exons) {
    foreach my $sf (@{$e->get_all_supporting_features}) {
      unless($sf->isa("Bio::EnsEMBL::BaseAlignFeature")){
        die("$sf must be an align feature otherwise it can't be stored");
      }

      #sanity check
      eval { $sf->validate(); };
      if ($@) {
        print ("Supporting feature invalid. Skipping feature\n");
        next;
      }


      $sf->contig($e->contig);
      if($sf->isa("Bio::EnsEMBL::DnaDnaAlignFeature")){
        $dna_adaptor->store($sf);
        $type = 'dna_align_feature';
      }elsif($sf->isa("Bio::EnsEMBL::DnaPepAlignFeature")){
        $pep_adaptor->store($sf);
        $type = 'protein_align_feature';
      } else {
        print("Supporting feature of unknown type. Skipping : [$sf]\n");
        next;
      }

      # print $sf_sth->{Statement} . "\n";
      # print "   values would have been exon " . $exon->dbID . " feature " . $sf->dbID . " type $type\n";
      $sf_sth->execute($exon->dbID, $sf->dbID, $type);
    }
  }
}
