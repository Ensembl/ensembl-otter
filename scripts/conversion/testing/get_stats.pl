#!/usr/local/bin/perl

use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs2a';
my $user   = 'ensro';
my $dbname = 'steve_chr20_vegadb';
my @chromosomes;
my $file = 'stdout';

my $path = 'NCBI_30';
my $port = 3306;

$| = 1;

&GetOptions(
  'host:s'   => \$host,
  'user:s'   => \$user,
  'dbname:s' => \$dbname,
  'path:s'   => \$path,
  'port:n'   => \$port,
  'chromosomes:s' => \@chromosomes,
  'file:s' => \$file
);

if (scalar(@chromosomes)) {
  @chromosomes = split(/,/,join(',',@chromosomes));
}

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -dbname => $dbname
);
$db->assembly_type($path);

my $sa = $db->get_SliceAdaptor();
my $ga = $db->get_GeneAdaptor();

my $chrhash = get_chrlengths($db);

#filter to specified chromosome names only
if (scalar(@chromosomes)) {
  foreach my $chr (@chromosomes) {
    my $found = 0;
    foreach my $chr_from_hash (keys %$chrhash) {
      if ($chr_from_hash =~ /^${chr}$/) {
        $found = 1;
        last;
      }
    }
    if (!$found) {
      print "Didn't find chromosome named $chr in database $dbname\n";
    }
  }
  HASH: foreach my $chr_from_hash (keys %$chrhash) {
    foreach my $chr (@chromosomes) {
      if ($chr_from_hash =~ /^${chr}$/) {next HASH;}
    }
    delete($chrhash->{$chr_from_hash});
  }
}


if ($file ne "stdout") {
  open FP,">$file";
} else {
  open FP,">-";
}

foreach my $chr (reverse sort bychrnum keys %$chrhash) {
  print STDERR "Chr $chr from 1 to " . $chrhash->{$chr}. "\n";
  my $chrstart = 1;
  my $chrend   = $chrhash->{$chr};

  my $slice = $sa->fetch_by_chr_name($chr);

  print "Fetching genes\n";
  my $genes = $slice->get_all_Genes;
  print "Done fetching genes\n";

  my $n_translation = 0;
  my $n_transcript = 0;
  my $n_gene  = 0;
  my $n_complete = 0;
  my $n_pseudo = 0;
  my $max_alt_trans = 0;
  my $max_alt_trans_gene = undef;
  
  my %transcript_counts;
  my %translation_counts;
  my %gene_counts;
  my %complete_counts;

  foreach my $gene (@$genes) {
    $n_gene++;
    my $transcripts = $gene->get_all_Transcripts;

    if (scalar(@$transcripts) > $max_alt_trans) {
      $max_alt_trans = scalar(@$transcripts);
      $max_alt_trans_gene = $gene;
    }

    $gene_counts{$gene->type} ++;
    $transcript_counts{$gene->type} += scalar(@$transcripts);

    foreach my $trans (@$transcripts) {
      $n_transcript++;
      if ($trans->translation) {
        $translation_counts{$gene->type}++;
        $n_translation++;
        if (check_start_and_stop($slice,$trans)) {
          #print "Transcript " .$trans->stable_id . " is complete\n";
          $n_complete++;
          $complete_counts{$gene->type}++;
        }
      }
    }
  }
  print "no. gene        = $n_gene\n";
  print "no. transcripts = $n_transcript\n";
  print "no. translation = $n_translation\n";
  print "no. complete    = $n_complete\n";

  printf "%-25s | %-13s | %-13s | %-13s | %-13s | %-13s\n", 
         "Type" , "#Genes", "#Transcripts", "#Translations", "#NComplete", "Ave Tscript/Gene"; 
  foreach my $type (keys %gene_counts) {
    printf "%-25s | %13d | %13d | %13d | %13d | %13.3f\n", $type, $gene_counts{$type}, $transcript_counts{$type},  
           (defined($translation_counts{$type}) ? $translation_counts{$type} : 0),
           (defined($complete_counts{$type}) ? $complete_counts{$type} : 0),
           ($transcript_counts{$type} / $gene_counts{$type});
  }

  printf "\nAverage transcripts per gene (excluding pseudogenes) = %7.3f\n",
    (($n_transcript-$transcript_counts{'HUMACE-Pseudogene'})/($n_gene-$gene_counts{'HUMACE-Pseudogene'}));
  
  print "\nMax alt transcripts = $max_alt_trans for " . $max_alt_trans_gene->stable_id."\n";
}


# End main


sub bychrnum {

  my @awords = split /_/, $a;
  my @bwords = split /_/, $b;

  my $anum = $awords[0];
  my $bnum = $bwords[0];

  #  if ($anum !~ /^chr/ || $bnum !~ /^chr/) {
  #    die "Chr name doesn't begin with chr for $a or $b";
  #  }

  $anum =~ s/chr//;
  $bnum =~ s/chr//;

  if ($anum !~ /^[0-9]*$/) {
    if ($bnum !~ /^[0-9]*$/) {
      return $anum cmp $bnum;
    } else {
      return 1;
    }
  }
  if ($bnum !~ /^[0-9]*$/) {
    return -1;
  }

  if ($anum <=> $bnum) {
    return $anum <=> $bnum;
  } else {
    if ($#awords == 0) {
      return -1;
    } elsif ($#bwords == 0) {
      return 1;
    } else {
      return $awords[1] cmp $bwords[1];
    }
  }
}

sub get_chrlengths {
  my $db   = shift;
  my $type = shift;

  if (!$db->isa('Bio::EnsEMBL::DBSQL::DBAdaptor')) {
    die "get_chrlengths should be passed a Bio::EnsEMBL::DBSQL::DBAdaptor\n";
  }

  my $ca = $db->get_ChromosomeAdaptor();
  my $chroms = $ca->fetch_all();

  my %chrhash;

  foreach my $chr (@$chroms) {
    $chrhash{$chr->chr_name} = $chr->length;
  }
  return \%chrhash;
}

sub check_start_and_stop {
  my ($vc,$trans) = @_;

  my @translatable = @{$trans->get_all_translateable_Exons};
  my $start_startc;
  my $end_startc;
  my $phase_startc;
  my $start_termc;
  my $end_termc;
  my $phase_termc;
  my $start_codon;
  my $stop_codon;


  if ($translatable[0]->strand == 1) {
    $start_startc = $translatable[0]->start;
    $end_startc   = $translatable[0]->start+2;
    $phase_startc = $translatable[0]->phase;

#    $start_termc = $translatable[$#translatable]->end+1;
#    $end_termc   = $translatable[$#translatable]->end+3;
    $start_termc = $translatable[$#translatable]->end-2;
    $end_termc   = $translatable[$#translatable]->end;
    $phase_termc = $translatable[$#translatable]->phase;

    #print "Forward strand start startc =  $start_startc end_startc = $end_startc start_termc = $start_termc end_termc = $end_termc\n";
    $start_codon = uc $vc->subseq($start_startc, $end_startc);
    $stop_codon  = uc $vc->subseq($start_termc, $end_termc);
  } else {
    $end_startc   = $translatable[0]->end;
    $start_startc = $translatable[0]->end-2;
    $phase_startc = $translatable[0]->phase;

    #$start_termc = $translatable[$#translatable]->start-3;
    #$end_termc   = $translatable[$#translatable]->start-1;
    $start_termc = $translatable[$#translatable]->start;
    $end_termc   = $translatable[$#translatable]->start+2;
    $phase_termc = $translatable[$#translatable]->phase;

    #print "Reverse strand start startc =  $start_startc end_startc = $end_startc start_termc = $start_termc end_termc = $end_termc\n";

    my $seqobj = Bio::PrimarySeq->new ( -seq => $vc->subseq($start_startc,$end_startc),
                              -moltype => 'dna'
                              );
    $start_codon = uc $seqobj->revcom->seq;
    $seqobj = Bio::PrimarySeq->new ( -seq => $vc->subseq($start_termc,$end_termc),
                              -moltype => 'dna'
                              );
    $stop_codon = uc $seqobj->revcom->seq;
  }

  #print "Start codon = $start_codon Stop codon = $stop_codon\n";
  if ($start_codon ne "ATG") {
    return 0;
  }
  if ($stop_codon ne "TGA" && $stop_codon ne "TAA" && $stop_codon ne "TAG") {
    return 0;
  }
  return 1;
}

