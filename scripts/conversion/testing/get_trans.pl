#!/usr/local/bin/perl


use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs1d';
my $user   = 'ensro';
my $dbname = 'test_ag2o';
my @chromosomes;
my $file = 'stdout';

my $path = 'NCBI_30';
my $port = 19322;

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

  foreach my $gene (@$genes) {
    my $ntranslating = 0;
    my $nnottranslating = 0;
    foreach my $trans (@{$gene->get_all_Transcripts}) {
      $trans->sort;
      my $translation = $trans->translation;
      if (defined($translation)) {
        print "Translation for " . $trans->stable_id . " = "  . $translation . " id = " . $trans->_translation_id ."\n";
        print " coords " . $trans->start . " to " . $trans->end . "\n";
        my $pepstr = $trans->translate->seq;
        if ($file ne "stdout") {
          print FP ">" . $trans->stable_id . " " . $trans->start . " ". $trans->end. "\n";
          print FP "$pepstr\n";
        } 
        if ($pepstr =~ /\*/) {
          print "Translation of transcript " . $trans->stable_id . " contains stop codons\n";
        }
        $ntranslating++;
      } else {
        print "No translation for " . $trans->stable_id . " of gene type " . $gene->type . "\n";
        print " coords " . $trans->start . " to " . $trans->end . "\n";
        $nnottranslating++;
      }
    }
    print "Gene " . $gene->stable_id . " has " . $ntranslating . " translating transcripts  and " . $nnottranslating . " non translating transcripts\n";
  }
  foreach my $gene (@$genes) {
    print "Gene " . $gene->stable_id  ." extents = " . $gene->start . " to " . $gene->end . " length " . ($gene->end-$gene->start+1) ."\n";
  }

  foreach my $gene (@$genes) {
    foreach my $trans (@{$gene->get_all_Transcripts}) {
      $trans->sort;
      my $prev_pnt = undef;
      foreach my $exon (@{$trans->get_all_Exons}) {
        if ($exon->strand == 1) {
          if (defined($prev_pnt)) {
            if ($exon->start-1 == $prev_pnt) {
    print "Gene " . $gene->stable_id  ." extents = " . $gene->start . " to " . $gene->end . "\n";
              print "Sticky bit in " . $trans->stable_id . "\n";
            }
          }
          $prev_pnt = $exon->end;
        } else {
          if (defined($prev_pnt)) {
            if ($exon->end+1 == $prev_pnt) {
    print "Gene " . $gene->stable_id  ." extents = " . $gene->start . " to " . $gene->end . "\n";
              print "Sticky bit in " . $trans->stable_id . "\n";
            }
          }
          $prev_pnt = $exon->start;
        }
        
      }
    }
  }


  foreach my $g (@$genes) {
    foreach my $tran (@{$g->get_all_Transcripts}) {
        my $tranid = $g->stable_id . ":" . $tran->stable_id;
        $tcount++;
        if (defined($tran->translation)) {
          my $prev_exon = undef;
          my $last_nonsticky = undef;
          $tran->sort;
          my @corrected_exons;
#          my @translating_exons = tweak_translateable($tran);
#          foreach my $exon (@translating_exons) {
          foreach my $exon (@{$tran->get_all_Exons}) {
            my $issticky = 0;
            if (defined($prev_exon)) {
              if ($prev_exon->end == $exon->start-1 && $exon->strand == 1) {
                print "Adding to sticky for exons " . $prev_exon->stable_id . " and " . $exon->stable_id . "\n";
                $issticky = 1;
                $last_nonsticky->end($exon->end);
              } elsif ($prev_exon->start == $exon->end+1 && $exon->strand == -1) {
                $issticky = 1;
                print "Adding to sticky for exons " . $prev_exon->stable_id . " and " . $exon->stable_id . "\n";
                $last_nonsticky->start($exon->start);
              }
            }
            if (!$issticky) {
              push @corrected_exons,$exon;
              $last_nonsticky = $exon;
            }
            $prev_exon = $exon;
          }
          foreach my $exon (@corrected_exons) {
            my $strand = "+";
            if ($exon->strand == -1) {
                $strand = "-";
            }
            my $phase = ".";
            if (defined($exon->phase)) {
              $phase = $exon->phase;
            }
 #            print $exon->stable_id . "\t$genetype\texon\t" . ($offset+$exon->start) . "\t" . ($offset+$exon->end) . "\t100" . "\t" . $strand . "\t" . $phase . "\t" . $tranid . "\n";
#            if ($exon->seqname eq $vc->id) {
#              print $exon->stable_id . "\t$genetype\texon\t" . ($offset+$exon->start) . "\t" . ($offset+$exon->end) . "\t100" . "\t" . $strand . "\t" . $phase . "\t" . $tranid . "\n";
#            } else {
#              print "Exon not on path\n";
#            }
          }
       }
    }
  }

  foreach my $gene (@$genes) {
    $gene->transform;
    foreach my $trans (@{$gene->get_all_Transcripts}) {
      foreach my $exon (@{$trans->get_all_Exons}) {
        if ($exon->isa("Bio::EnsEMBL::StickyExon")) {
          print "Sticky exon " . $exon->stable_id . " in " . $trans->stable_id . "\n";
        }
      }
    }
  }
}

sub tweak_translateable {
  my ($trans) = @_;

  my @exons = @{$trans->get_all_translateable_Exons};

# The start and end exons may have been clipped
# This hack gives them the stable_id of the unclipped exon
  $exons[0]->stable_id($trans->translation->start_Exon->stable_id);
  $exons[$#exons]->stable_id($trans->translation->end_Exon->stable_id);

  return @exons;
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

