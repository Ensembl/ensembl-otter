package Bio::Otter::Converter;

use strict;

use Bio::Otter::Author;
use Bio::Otter::AnnotatedGene;
use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::GeneInfo;
use Bio::Otter::Evidence;
use Bio::Otter::GeneRemark;
use Bio::Otter::GeneName;
use Bio::Otter::GeneSynonym;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::TranscriptClass;

use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::RawContig;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Clone;
use Bio::Seq;


sub XML_to_otter {
  my $fh = shift;
  my $db = shift;

  my $gene = undef;
  my $tran;
  my $exon;
  my $author;
  my $geneinfo;
  my $traninfo;
  my $evidence;
  my $currentobj;
  my $slice;
  my $seqstr        = undef;
  my $tl_start      = undef;
  my $tl_end        = undef;
  my $assembly_type = undef;
  my %frag;
  my $currfragname;
  my @genes;
  my $foundend = 0;
  my $time_now = time;

  while (<$fh>) {
    chomp;

    if (/<locus>/) {
      if (defined($gene)) {
        $gene->gene_info->author($author);
      }

      $gene = new Bio::Otter::AnnotatedGene();

      push (@genes, $gene);

      $geneinfo = new Bio::Otter::GeneInfo;

      $gene->gene_info($geneinfo);

      $author     = new Bio::Otter::Author;
      $currentobj = 'gene';

      undef($tran);
    } elsif (/<locus_type>(.*)<\/locus_type>/) {
      if ($currentobj ne $1) {
        print STDERR "EEEK! Wrong locus type [$currentobj][$1]\n";
      }
    } elsif (/<stable_id>(.*)<\/stable_id>/) {
      my $stable_id = $1;

      if ($currentobj eq 'gene') {
        $gene->stable_id($stable_id);
        $gene->version(1);
        $gene->created($time_now);
        $gene->modified($time_now);
      } elsif ($currentobj eq 'tran') {
        $tran->stable_id($stable_id);
        $tran->version(1);
      } elsif ($currentobj eq 'exon') {
        $exon->stable_id($stable_id);
        $exon->version(1);
        $exon->created($time_now);
        $exon->modified($time_now);

        #$tran->add_Exon($exon);
      } else {
        print "ERROR: Current obj is $currentobj -can only add stable ids to gene,tran,exon\n";
      }
    } elsif (/<remark>(.*)<\/remark>/) {
      my $remark = $1;

      if ($currentobj eq 'gene') {
        my $rem = new Bio::Otter::GeneRemark(-remark => $remark);
        $geneinfo->remark($rem);
      } elsif ($currentobj eq 'tran') {
        my $rem = new Bio::Otter::TranscriptRemark(-remark => $remark);
        $traninfo->remark($rem);
      } else {
        print "ERROR: Current obj is $currentobj -can only add remarks to gene,tran\n";
      }
    } elsif (/<translation_start>(.*)<\/translation_start>/) {
      $tl_start = $1;

      if ($currentobj eq 'tran') {
      } else {
        print "ERROR: Current obj is $currentobj -can only add translation start to tran\n";
      }
    } elsif (/<translation_end>(.*)<\/translation_end>/) {
      $tl_end = $1;

      if ($currentobj eq 'tran') {
      } else {
        print "ERROR: Current obj is $currentobj -can only add translation end to tran\n";
      }

    } elsif (/<author>(.*)<\/author>/) {
      my $name = $1;

      $author->name($name);
    } elsif (/<author_email>(.*)<\/author_email>/) {
      my $email = $1;

      $author->email($email);
    } elsif (/<dna>/) {
      # print STDERR "Found dna\n";
      if (defined($seqstr)) {
        die "ERROR: Got more than one dna record\n";
      } 
      $currentobj = 'dna';
    } elsif (/<transcript>/) {

      $tran     = new Bio::Otter::AnnotatedTranscript;
      $traninfo = new Bio::Otter::TranscriptInfo;

      $tran->transcript_info($traninfo);
      $traninfo->author($author);

      $currentobj = 'tran';

      $gene->add_Transcript($tran);
    } elsif (/<\/transcript>/) {

      # At end of transcript section need to position translation 
      # if there is one. We need to do this after we have all the
      # exons 
      if (defined($tl_start) && defined($tl_end)) {

        #print "Setting translation to $tl_start and $tl_end\n";
        my ($start_exon, $start_pos) = exon_pos($tran, $tl_start);
        my ($end_exon,   $end_pos)   = exon_pos($tran, $tl_end);

        if (!defined($start_exon) || !defined($end_exon)) {
          print "ERROR: Failed mapping translation to transcript\n";
        } else {
          my $translation = new Bio::EnsEMBL::Translation;
          $translation->start_Exon($start_exon);
          $translation->start($start_pos);
          if ($start_exon->strand == 1 && $start_exon->start != $tl_start) {
            #$start_exon->phase(-1);
            $start_exon->end_phase(($start_exon->length-$start_pos+1)%3);
          } elsif ($start_exon->strand == -1 && $start_exon->end != $tl_start) {
            #$start_exon->phase(-1);
            $start_exon->end_phase(($start_exon->length-$start_pos+1)%3);
          }
          $translation->end_Exon($end_exon);
          $translation->end($end_pos);
          if ($end_exon->length != $end_pos) {
            $end_exon->end_phase(-1);
          }
          $tran->translation($translation);
        }
       } elsif (defined($tl_start) || defined($tl_end)) {
        print "ERROR: Either translation start or translation end undefined\n";
      }
      $tl_start = undef;
      $tl_end   = undef;
    } elsif (/<cds_start_not_found>(.*)<\/cds_start_not_found>/) {

      if (defined($1) && $1 ne "") {

        #if (defined($1)) {
        $traninfo->cds_start_not_found(($1 eq "") ? 0 : $1);
      }
    } elsif (/<cds_end_not_found>(.*)<\/cds_end_not_found>/) {
      if (defined($1) && $1 ne "") {

        #if (defined($1)) {
        $traninfo->cds_end_not_found(($1 eq "") ? 0 : $1);
      }
    } elsif (/<mRNA_start_not_found>(.*)<\/mRNA_start_not_found>/) {
      if (defined($1) && $1 ne "") {

        #if (defined($1)) {
        $traninfo->mRNA_start_not_found(($1 eq "") ? 0 : $1);
      }
    } elsif (/<mRNA_end_not_found>(.*)<\/mRNA_end_not_found>/) {
      if (defined($1) && $1 ne "") {

        #if (defined($1)) {
        $traninfo->mRNA_end_not_found(($1 eq "") ? 0 : $1);
      }
    } elsif (/<transcript_class>(.*)<\/transcript_class>/) {
      if (defined($1) && $1 ne "") {
        $traninfo->class(new Bio::Otter::TranscriptClass(-name => $1));
      }
    } elsif (/<exon>/) {
      $exon = new Bio::EnsEMBL::Exon();

      $currentobj = 'exon';
    } elsif (/<start>(.*)<\/start>/) {
      $exon->start($1);
    } elsif (/<end>(.*)<\/end>/) {
      $exon->end($1);
    } elsif (/<strand>(.*)<\/strand>/) {
      $exon->strand($1);
    } elsif (/<frame>(.*)<\/frame>/) {
      $exon->phase((3-$1)%3);
    } elsif (/<\/exon>/) {
      if (defined($exon->phase)) {
        $exon->end_phase(($exon->length + $exon->phase)%3);
      } else {
        $exon->phase(-1);
        $exon->end_phase(-1);
      }
      $tran->add_Exon($exon);
    } elsif (/<evidence>/) {
      $evidence = new Bio::Otter::Evidence;
      $traninfo->evidence($evidence);
      $currentobj = 'evidence';
    } elsif (/<name>(.*)<\/name>/) {

      if ($currentobj eq 'evidence') {
        $evidence->name($1);
      } elsif ($currentobj eq 'tran') {
        $traninfo->name($1);
      } elsif ($currentobj eq 'gene') {
        $geneinfo->name(new Bio::Otter::GeneName(-name => $1));
      } else {
        die "ERROR: name tag only associated with evidence or transcript - obj is $currentobj\n";
      }
    } elsif (/<\/evidence_set>/) {
      $currentobj = 'tran';
    } elsif (/<synonym>(.*)<\/synonym>/) {

      if ($currentobj eq 'gene') {
        my $syn = new Bio::Otter::GeneSynonym(-name => $1);
        $geneinfo->synonym($syn);
      } else {
        die "ERROR: synonym tag only associated with gene objects. Object is [$currentobj]\n";
      }
    } elsif (/<type>(.*)<\/type>/) {

      if ($currentobj eq 'evidence') {
        $evidence->type($1);
      } else {
        die "ERROR: type tag only associated with evidence - obj is $currentobj\n";
      }
    } elsif (/<sequencefragment>/) {
      $currentobj = 'frag';
    } elsif (/<assembly_type>(.*)<\/assembly_type>/) {
      $assembly_type = $1;
    } elsif (/<chromosome>(.*)<\/chromosome>/) {
      my $chr = $1;
      $frag{$currfragname}{chr} = $chr;
    } elsif (/<assemblystart>(.*)<\/assemblystart>/) {
      $frag{$currfragname}{start} = $1;
    } elsif (/<id>(.*)<\/id>/) {
      $currfragname = $1;

      if ($currentobj eq 'frag') {
        $frag{$currfragname}{id} = $1;
      }
    } elsif (/<assemblyend>(.*)<\/assemblyend>/) {
      $frag{$currfragname}{end} = $1;
    } elsif (/<assemblyori>(.*)<\/assemblyori>/) {
      $frag{$currfragname}{strand} = $1;
    } elsif (/<assemblyoffset>(.*)<\/assemblyoffset>/) {
      $frag{$currfragname}{offset} = $1;
    } elsif (/<.*?>.*<\/.*?>/) {
      print "ERROR: Unrecognised tag [$_]\n";
    } elsif (!/</ && !/>/) {
      if ($currentobj eq 'dna') {
        s/^\s*//;
        s/\s*$//;
        $seqstr .= $_;
        if (length($seqstr)%1000000 < 100) {
          #print STDERR "Found seq " . length($seqstr) . "\n";
        }
      }
    } elsif (/<\/otter>/) {
      $foundend = 1;
    }
  }

  if (!$foundend) {
     print STDERR "Didn't find end tag <\/otter>\n";
  }
  # Make the sequence fragments
  my @fragnames = keys %frag;
  my @contigs;

  my $chrname  = "";
  my $chrstart = 2000000000;
  my $chrend   = -1;

  foreach my $f (@fragnames) {
    if ($chrname eq "") {
      $chrname = $frag{$f}{chr};
    } elsif ($chrname ne $frag{$f}{chr}) {
      print "fname = " . $f . "\n";
      print "frag id = " . $frag{$f}{id} . "\n";
      die " Chromosome names are different - can't make slice [$chrname]["
        . $frag{$f}{chr} . "]\n";
    }

    if (!defined($chrstart)) {
      $chrstart = $frag{$f}{start};
    } elsif ($frag{$f}{start} < $chrstart) {
      $chrstart = $frag{$f}{start};
    }

    if ($frag{$f}{end} > $chrend) {
      $chrend = $frag{$f}{end};
    }
  }

  @fragnames = sort { $frag{$a}{start} <=> $frag{$b}{start} } @fragnames;

  # print STDERR "chrname = " . $chrname . " chrstart = " . $chrstart . " chrend = "
  #  . $chrend . "\n";
  if (defined($db)) {
    if ($assembly_type) {
      $db->assembly_type($assembly_type);
    }
    my $sa    = $db->get_SliceAdaptor;
    my $slice = $sa->fetch_by_chr_start_end($chrname, $chrstart, $chrend);

    my @path = @{ $slice->get_tiling_path };
  
# Only store slice if no tiling path returned
# Then refetch slice
    if (!scalar(@path)) {
      Bio::Otter::Converter::frags_to_slice($chrname,$chrstart,$chrend,$assembly_type,$seqstr,\%frag,$db);
      $sa    = $db->get_SliceAdaptor;
      $slice = $sa->fetch_by_chr_start_end($chrname, $chrstart, $chrend);

      @path = @{ $slice->get_tiling_path };
    }


    foreach my $p (@path) {
      my $fragname = shift @fragnames;
      if ($p->component_Seq->name ne $fragname
        || ($slice->chr_start + $p->assembled_start - 1) !=
        $frag{$fragname}{start}
        || ($slice->chr_start + $p->assembled_end - 1) != $frag{$fragname}{end})
      {
        die "Assembly doesn't match for contig $fragname";
      }
    }
  }

  if (defined($gene)) {
    $gene->gene_info->author($author);
  }

  # The xml coordinates are all in chromosomal coords - these
  # Need to be converted back to slice coords 
  if ($chrstart != 2000000000) {
    foreach my $gene (@genes) {
      foreach my $exon (@{ $gene->get_all_Exons }) {
        $exon->start($exon->start - $chrstart + 1);
        $exon->end($exon->end - $chrstart + 1);
      }
    }
  }

  foreach my $gene (@genes) {
    prune_Exons($gene);

    foreach my $tran (@{$gene->get_all_Transcripts}) {
        my @exons = @{$tran->get_all_Exons};
        if ($exons[0]->strand == 1) {
           @exons = sort {$a->start <=> $b->start} @exons;
        } else {
           @exons = sort {$b->start <=> $a->start} @exons;
        }
        $tran->{_trans_exon_array} = \@exons;
    }
  }

  return (\@genes, $chrname, $chrstart, $chrend,$assembly_type,$seqstr);
}

sub otter_to_ace {
  my ($contig, $genes, $path) = @_;
  
  my $str =  "Sequence : \"" . $contig->display_id . "\"\nGenomic_canonical\n";

  print "Contig $contig\n";
  if ($contig->isa("Bio::EnsEMBL::Slice")) {
    my $slice = $contig;

    $str .= "Assembly_name " . $path . "\n";

  my @path  = @{ $slice->get_tiling_path };

  my $chr      = $slice->chr_name;
  my $chrstart = $slice->chr_start;
  my $chrend   = $slice->chr_end;

    foreach my $path (@path) {
       my $start;
       my $end;
    
       if ($path->component_ori == 1) {
         $start = $chrstart + $path->assembled_start - 1;
         $end   = $chrstart + $path->assembled_end - 1;
       } else {
         $end     = $chrstart + $path->assembled_start - 1 ;
         $start   = $chrstart + $path->assembled_end - 1;
       } 
       $str .= "Feature TilePath " . $start . " " . $end . " 1.0 " . $path->component_Seq->name . "\n";
    }
  }
  foreach my $gene (@$genes) {
  
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
      $str .= "Subsequence   \"" . $tran->stable_id . "\" ";
      my @exons = @{ $tran->get_all_Exons };
      if ($exons[0]->strand == 1) {
        @exons = sort {$a->start <=> $b->start} @exons;
        $tran->{_trans_exon_array} = \@exons;
        $str .= $tran->start . " " . $tran->end . "\n";
      } else {
        @exons = sort {$b->start <=> $a->start} @exons;
        $tran->{_trans_exon_array} = \@exons;
        $str .= $tran->end . " " . $tran->start . "\n";
      }
    }
  }

  #Clone start end, features, keywords?
  $str .= "\n";

  my %ev_types = (
    'EST'     => "EST_match",
    'cDNA'    => "cDNA_match",
    'Protein' => "Protein_match",
    'Genomic' => "Genomic_match"
  );

  # Need correct TR and WP mappings
  my %dbhash = (
    "EMBL"       => "EM",
    "SWISSPROT"  => "SW",
    "protein_id" => "UNK",
  );

  foreach my $gene (@$genes) {
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
      $str .= "Sequence : \"" . $tran->stable_id . "\"\n";
      $str .= "Source \"" . $contig->display_id . "\"\n";
      $str .= "Locus \"" . $gene->stable_id . "\"\n";
      $str .= "Method \"" . $tran->transcript_info->class->name . "\"\n";

      my @remark = $tran->transcript_info->remark;

      @remark = sort {$a->remark cmp $b->remark} @remark;

      foreach my $rem (@remark) {
        $str .= "Remark \"" . $rem->remark . "\"\n";
      }

      my @ev = $tran->transcript_info->evidence;

      @ev = sort {$a->name cmp $b->name} @ev;

      foreach my $ev (@ev) {
        $str .= $ev_types{ $ev->type } . " \"" . $dbhash{ $ev->db_name } . ":"
          . $ev->name . "\"\n";
      }

      $tran->sort;
      my $trans_off;
      my @exons = @{ $tran->get_all_Exons };

      if ($exons[0]->strand == 1) {
        $trans_off = $tran->start - 1;
      } else {
        $trans_off = $tran->end + 1;
      }

      foreach my $exon (@exons) {
        if ($exons[0]->strand == 1) {
          $str .= "Source_Exons " . ($exon->start - $trans_off) . " "
            . ($exon->end - $trans_off) . "\n";
        } else {
          $str .= "Source_Exons " . ($trans_off - $exon->end) . " "
            . ($trans_off - $exon->start) . "\n";
        }
      }

      if ($tran->translation) {
        my $translation = $tran->translation;

        #Need to check putting Predicted_gene here is OK
        $str .= "Predicted_gene\n";
        $str .= "CDS ";
        if ($exons[0]->strand == 1) {
          $str .= rna_pos($tran, $tran->coding_start) . " ";
          $str .= rna_pos($tran, $tran->coding_end) . "\n";
        } else {
          $str .= rna_pos($tran, $tran->coding_end) . " ";
          $str .= rna_pos($tran, $tran->coding_start) . "\n";
        }
      }

      # Note need to fix for Start_not_found n
      if ($tran->transcript_info->cds_start_not_found
        || $tran->transcript_info->mRNA_start_not_found)
      {
        $str .= "Start_not_found\n";
      }

      if ($tran->transcript_info->cds_end_not_found
        || $tran->transcript_info->mRNA_end_not_found)
      {
        $str .= "End_not_found\n";
      }

      $str .= "\n";
    }
    $str .= "\n";
  }

  $str .= "\n";

  foreach my $gene (@$genes) {
    $str .= "Locus : \"" . $gene->stable_id . "\"\n";

    #Need to add type here
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
      $str .= "Positive_sequence  \"" . $tran->stable_id . "\"\n";
    }
    $str .= "\n";
  }

  # Finally the dna
  $str .= "\nDNA \"" . $contig->display_id . "\"\n";
  my $seq = $contig->seq;

  $seq =~ s/(.{72})/$1\n/g;
  $str .= $seq;
  return $str;
}

sub rna_pos {
  my ($tran, $loc) = @_;

  my $start;
  my $end;

  if ($tran->start_Exon->strand == 1) {
    $start = $tran->start_Exon->start;
  } else {
    $start = $tran->start_Exon->end;
  }

  if ($tran->end_Exon->strand == 1) {
    $end = $tran->end_Exon->end;
  } else {
    $end = $tran->end_Exon->start;
  }

  print "start = " . $start;
  print " end = " . $end;
  print " loc = " . $loc . "\n";

  if ($tran->start_Exon->strand == 1) {
    return undef if $loc < $start;
    return undef if $loc > $end;
  } else {
    return undef if $loc > $start;
    return undef if $loc < $end;
  }

  my $mrna = 1;

  my $prev = undef;
  foreach my $exon (@{ $tran->get_all_Exons }) {

    my $tmp = $exon->length;
    print "Exon " . $exon->stable_id . " " . $exon->start . "\t" . $exon->end . "\t" . $exon->strand . "\t" . $exon->phase . "\t" . $exon->end_phase. "\n";
    if ($prev) {
      if ($prev->end_phase != -1 && $prev->end_phase != $exon->phase) {
        print STDERR "Monkey exons in transcript\n";
      }
    }

    if ($loc <= $exon->end && $loc >= $exon->start) {
      if ($exon->strand == 1) {
        return ($loc - $exon->start) + $mrna;
      } else {
        return ($exon->end - $loc) + $mrna;
      }
    }
    $mrna += ($tmp);
    $prev = $exon;
  }
  print "Returning undef\n";
  return undef;
}

sub exon_pos {
  my ($tran, $loc) = @_;

  foreach my $exon (@{ $tran->get_all_Exons }) {

    if ($loc <= $exon->end && $loc >= $exon->start) {
      if ($exon->strand == 1) {
        return ($exon, ($loc - $exon->start) + 1);
      } else {
        return ($exon, ($exon->end - $loc) + 1);
      }
    }
  }
  return (undef, undef);
}

sub ace_to_otter {
  my ($fh) = shift;

  my %sequence;

  my $currtran;
  my $contig;

  my @tran;
  my %genes;
  my %genenames;

  while (<$fh>) {

    chomp;
    $_ =~ s/\t//g;

    if (/^Sequence +: +\"(.*)\"/) {
      my $currname = $1;

      #print STDERR "Found sequence [$currname]\n";

      while (($_ = <$fh>) !~ /^\n$/) {
        chomp;
        $_ =~ s/\t//g;

        if (/^Subsequence\s+(\S+)\s+(\d+)\s+(\d+)/) {
          my $name  = $1;
          my $start = $2;
          my $end   = $3;

          $name =~ s/\"//g;

          #print STDERR "Name $name $start $end\n";

          my $strand = 1;

          if ($start > $end) {
            $strand = -1;
            my $tmp = $start;
            $start = $end;
            $end   = $tmp;
          }

          $sequence{$name}{start}  = $start;
          $sequence{$name}{end}    = $end;
          $sequence{$name}{parent} = $currname;
          $sequence{$name}{strand} = $strand;

        } elsif (/^Genomic_canonical/) {

          #print "Found contig\n";

          if (defined($contig)) {
            die "Only one Genomic_canonical sequence allowed\n";
          }

          $contig = new Bio::EnsEMBL::RawContig;
          $contig->name($currname);
        } elsif (/^Clone_left_end +(\S+) +(\d+)/) {
          my $val = $1;
          my $cle = $2;

          $val =~ s/\"//g;
          $sequence{$currname}{Clone_left_end}{$val} = $cle;

        } elsif (/^Clone_right_end +(\S+) +(\d+)/) {

          my $val = $1;
          my $cre = $2;

          $val =~ s/\"//g;
          $sequence{$currname}{Clone_right_end}{$val} = $cre;

        } elsif (/^Keyword +\"(.*)\"/) {

          if (!defined($sequence{$currname}{keyword})) {
            $sequence{$currname}{keyword} = [];
          }
          push (@{ $sequence{$currname}{keyword} }, $1);

        } elsif (/^EMBL_dump_info +DE_line \"(.*)\"/) {

          $sequence{$currname}{EMBL_dump_info} = $1;

        } elsif (/^Feature +(\S+) +(\d+) +(\d+) +(\d+) +(\S+)/) {

          my $val   = $1;
          my $val2  = $5;
          my $start = $2;
          my $end   = $3;
          my $score = $4;

          $val  =~ s/\"//g;
          $val2 =~ s/\"//g;

          # strand
          my $f = new Bio::EnsEMBL::SeqFeature(
            -name       => $val,
            -start      => $start,
            -end        => $end,
            -score      => $score,
            -gff_source => $val2
          );

          if (!defined($sequence{$currname}{feature})) {
            $sequence{$currname}{feature} = [];
          }
          push (@{ $sequence{$currname}{feature} }, $f);

        } elsif (/^Source +(\S+)/) {

          # We have a gene and not a contig.

          my $val = $1;
          $val =~ s/\"//g;

          $sequence{$currname}{Source} = $val;

          my $tran = new Bio::EnsEMBL::Transcript();
          $sequence{$currname}{transcript} = $tran;

          #print STDERR "new tran  $currname [$tran][$val]\n";
        } elsif (/^Source_Exons +(\d+) +(\d+)/) {
          my $oldstart = $1;
          my $oldend   = $2;

          my $tstart  = $sequence{$currname}{start};
          my $tend    = $sequence{$currname}{end};
          my $tstrand = $sequence{$currname}{strand};

          my $start;
          my $end;

          if ($tstrand == 1) {
            $start = $oldstart + $tstart - 1;
            $end   = $oldend + $tstart - 1;
          } else {
            $end   = $tend - $oldstart + 1;
            $start = $tend - $oldend + 1;
          }

          # print "Adding exon at $start $end to $currname\n";
          my $exon = new Bio::EnsEMBL::Exon(
            -start  => $start,
            -end    => $end,
            -strand => $tstrand
          );
          $sequence{$currname}{transcript}->add_Exon($exon);

        } elsif (/^Continues_as +(\S+)/) {

          $sequence{$currname}{Continues_as} = $1;

        } elsif (/^EST_match +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;

          if (!defined($sequence{$currname}{EST_match})) {
            $sequence{$currname}{EST_match} = [];
          }
          push (@{ $sequence{$currname}{EST_match} }, $val);
        } elsif (/^cDNA_match +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;

          if (!defined($sequence{$currname}{cDNA_match})) {
            $sequence{$currname}{cDNA_match} = [];
          }
          push (@{ $sequence{$currname}{cDNA_match} }, $val);

        } elsif (/^Protein_match +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;

          if (!defined($sequence{$currname}{Protein_match})) {
            $sequence{$currname}{Protein_match} = [];
          }
          push (@{ $sequence{$currname}{Protein_match} }, $val);

        } elsif (/^Genomic_match +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;

          if (!defined($sequence{$currname}{Genomic_match})) {
            $sequence{$currname}{Genomic_match} = [];
          }
          push (@{ $sequence{$currname}{Genomic_match} }, $val);

        } elsif (/^Locus +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;

          $genenames{$currname} = $val;

        } elsif (/^Remark +\"(.*)\"/) {

          if (!defined($sequence{$currname}{Remark})) {
            $sequence{$currname}{Remark} = [];
          }
          push (@{ $sequence{$currname}{Remark} }, $1);

        } elsif (/^Isoform +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;

          $sequence{$currname}{Isoform} = $val;

        } elsif (/^Predicted_gene/) {

          $sequence{$currname}{Predicted_gene} = 1;

        } elsif (/^CDS +(\d+) +(\d+)/) {

          $sequence{$currname}{CDS_start} = $1;
          $sequence{$currname}{CDS_end}   = $2;

        } elsif (/^End_not_found/) {

          $sequence{$currname}{End_not_found} = 0;

        } elsif (/^Start_not_found +(\d+)/) {

          #print "start not found with $1\n";    
          $sequence{$currname}{Start_not_found} = $1;

        } elsif (/^Start_not_found/) {

          $sequence{$currname}{Start_not_found} = 0;

        } elsif (/^Method +(\S+)/) {

          my $val = $1;
          $val =~ s/\"//g;
          $sequence{$currname}{Method} = $val;

        } elsif (/^Processed_mRNA/) {

          $sequence{$currname}{Processed_mRNA} = 1;

        } elsif (/^Pseudogene/) {

          $sequence{$currname}{Pseudogene} = 1;

        }
      }
    } elsif (/^DNA +(\S+)/) {
      my $name = $1;
      $name =~ s/\"//g;
      my $seq;
      my $line;

      while (defined($fh) && ($line = <$fh>) && $line !~ /^\n$/) {
        chomp($line);
        $seq .= $line;
      }
      $sequence{$name} = $seq;
    } elsif (/^Locus +: +(\S+)/) {
      my $name = $1;
      $name =~ s/\"//g;

      while (($_ = <$fh>) !~ /^\n$/) {
        $_ =~ s/\t//g;
        if (/^Known/) {
          $genes{$name}{GeneType} = "Known";
        } elsif (/^Putative/) {
          $genes{$name}{GeneType} = "Putative";
        } elsif (/^Pseudogene/) {
          $genes{$name}{GeneType} = "Pseudogene";
        } elsif (/^Organism_supported/) {
          $genes{$name}{GeneType} = "Organism_supported";
        } elsif (/^Positive_sequence +(\S+)/) {
          my $tranname = $1;
          $tranname =~ s/\"//g;

          if (!defined($genes{$name}{transcripts})) {
            $genes{$name}{transcripts} = [];
          }
          push (@{ $genes{$name}{transcripts} }, $tranname);
        }
      }
    }
  }

  #print "Contig pog $contig\n";
  my $contig_name = "";

  if (defined($contig->name)) { $contig_name = $contig->name; }

  #print "Name " . $contig_name . "\n";

  my %anntran;

  foreach my $seq (keys %sequence) {

    print "Seq = $seq\n";
    #print "Key $seq " . $sequence{$seq}{Source} . " " . $contig_name . "\n";
    if (defined($sequence{$seq}{Source})
      && $sequence{$seq}{Source} eq $contig_name)
    {
      my $traninfo = new Bio::Otter::TranscriptInfo;

# Start not found and end not found (should it ever be mRNA_start_not_found?)
      if ($sequence{$seq}{Method} =~ /RNA/) {
        $traninfo->mRNA_start_not_found(
          exists($sequence{$seq}{Start_not_found}) ? 1 : 0);
        $traninfo->mRNA_end_not_found(
          exists($sequence{$seq}{End_not_found}) ? 1 : 0);
      } else {
        $traninfo->cds_start_not_found(
          exists($sequence{$seq}{Start_not_found}) ? 1 : 0);
        $traninfo->cds_end_not_found(
          exists($sequence{$seq}{End_not_found}) ? 1 : 0);
      }

      # Remarks for the transcript
      if (defined($sequence{$seq}{Remark})) {
        my @rem = @{ $sequence{$seq}{Remark} };

        foreach my $rem (@rem) {
          my $remark = new Bio::Otter::TranscriptRemark(-remark => $rem);
          $traninfo->remark($remark);
        }
      }

      # Evidence for the transcript
      my @evidence;

      # TR should probably be trembl but its an enum in the db
      # WP should probably be wormpep but its an enum in the db
      my %dbhash = (
        "EM" => "EMBL",
        "Em" => "EMBL",
        "SW" => "SWISSPROT",
        "Sw" => "SWISSPROT",
        "sw" => "SWISSPROT",
        "TR" => "protein_id",
        "Tr" => "protein_id",
        "tr" => "protein_id",
        "WP" => "protein_id",
        "Wp" => "protein_id",
        "wp" => "protein_id"
      );

      foreach
        my $i (("EST_match", "cDNA_match", "Protein_match", "Genomic_match"))
      {

        if (defined($sequence{$seq}{$i})) {
          my @ev   = @{ $sequence{$seq}{$i} };
          my $type = $i;
          $type =~ s/_match//;

          foreach my $ev (@ev) {
            my ($db_abbrev, $name) = split /:/, $ev;

            my $db_name = $dbhash{$db_abbrev};

            #print "dbname = $db_name name = $name\n";
            my $obj = new Bio::Otter::Evidence(
              -type    => $type,
              -name    => $name,
              -db_name => $db_name,
            );
            push (@evidence, $obj);
          }
        }
      }
      $traninfo->evidence(@evidence);

      # Type of transcript (Method tag)
      my $class =
        new Bio::Otter::TranscriptClass(-name => $sequence{$seq}{Method});

      $traninfo->class($class);
      $traninfo->name($seq);

      #print "Defined $seq " . $sequence{$seq}{transcript} . "\n";
      if (defined($sequence{$seq}{transcript})) {
        my $anntran = bless $sequence{$seq}{transcript},
          "Bio::Otter::AnnotatedTranscript";

        $anntran->transcript_info($traninfo);

        $anntran{$seq} = $anntran;

        # Sort the exons here just in case 
        $anntran->sort;

        #print ("Anntran $seq [$anntran]\n");
        # Set the translation start and end

        # Set the phase of the transcript
        my $phase = $sequence{$seq}{Start_not_found};

        if (defined($phase) && $phase != 0) {
          $phase--;
        } else {
          $phase = 0;
        }

        #SMJS Added
        if ($phase == 1) {
          $phase = 2;
        } elsif ($phase == 2) {
          $phase = 1;
        }

        #SMJS End added
        # print "Phase for $seq exon = $phase\n";

        foreach my $exon (@{ $anntran->get_all_Exons }) {
          my $len      = $exon->end - $exon->start + 1;
          my $endphase = ($len + $phase) % 3;

          $exon->phase($phase);
          $exon->end_phase($endphase);

          $phase = $endphase;
        }
      }
    }
  }

  my @genes;

  foreach my $gname (keys %genes) {
    my $gene  = new Bio::Otter::AnnotatedGene;
    my $ginfo = new Bio::Otter::GeneInfo;

    $gene->gene_info($ginfo);
    print "Gene name = $gname\n";

    #$gene->stable_id($gname);
    $gene->gene_info->name(new Bio::Otter::GeneName(-name => $gname));

    #print STDERR "Made gene $gname\n";

    push (@genes, $gene);

    # We need to pair up the CDS transcript objects with the 
    # mRNA objects and set the translations

    my @newtran;

    TRAN: foreach my $tranname (@{ $genes{$gname}{transcripts} }) {
      my $tran = $anntran{$tranname};

      next TRAN unless defined($tran);

      # If we have mRNA in the name look for a CDS
      # with the same name without the .mRNA

      # Alternatively the CDS may have CDS_start and CDS_end
      # coordinates

      if ($tranname =~ /(.*?)\.mRNA$/) {

        # print STDERR "Got mrna $1 - finding CDS\n";

        my $cdsname = $1;

        TRAN2: foreach my $tname (@{ $genes{$gname}{transcripts} }) {

          # print STDERR "Name $tname \n";
          if ($tname eq $cdsname) {

            # print STDERR "Found CDS " . $tname . "\n";

            # We have found a matching cds for 
            # a mRNA.  We need to set the 
            # translation start and end points

            my $cds = $anntran{$tname};

            next TRAN2 unless defined($cds);

            my @exons = @{ $cds->get_all_Exons };

            my $cds_start;
            my $cds_end;

            my $start_phase;
            if ($exons[0]->strand == 1) {
              $cds_start   = $exons[0]->start;
              $cds_end     = $exons[$#exons]->end;
              $start_phase = $exons[0]->phase;
            } else {
              $cds_start   = $exons[0]->end;
              $cds_end     = $exons[$#exons]->start;
              $start_phase = $exons[0]->phase;
            }

            if (!exists($sequence{$tname}{Start_not_found})) {
              $start_phase = 0;
            }

# print "cds start = $cds_start cds end = $cds_end exon start = " . $exons[0]->start . " end " . $exons[0]->end . " phase " . $exons[0]->phase . " start_phase = " . $start_phase . " start_not_found = " . $sequence{$tname}{Start_not_found}. "\n";

            make_translation($tran, $cds_start, $cds_end, $start_phase);

          }
        }
      }

      if ($sequence{$tranname}{CDS_start}) {

        my $translation = new Bio::EnsEMBL::Translation;

        $tran->translation($translation);

        my $cds_start = $sequence{$tranname}{CDS_start};
        my $cds_end   = $sequence{$tranname}{CDS_end};

        # print "Found new CDS $tranname " . $cds_start . " " . $cds_end . "\n";

        make_translation_from_cds($tran, $cds_start, $cds_end);

      }
    }

    # We are left with the CDS only genes now

    TRAN3: foreach my $tranname (@{ $genes{$gname}{transcripts} }) {
      my $tran = $anntran{$tranname};

      next TRAN3 unless defined($tran);

      #print STDERR "Tran [$tranname][$tran]\n";
      if (defined($tran) && defined($tran->translation)) {

        # if (defined($tran)) {
        #$tran->stable_id($tranname);
        $gene->add_Transcript($tran);

        #print STDERR "Adding transcript\n";
      }
    }
    prune_Exons($gene);
  }
  return \@genes;
}

sub make_translation_from_cds {
  my ($tran, $cds_start, $cds_end) = @_;

  my @exons = @{ $tran->get_all_Exons };

  my $found_start = 0;
  my $found_end   = 0;

  my $start = 1;

  my $phase       = $exons[0]->phase;
  my $translation = $tran->translation;
  while (my $exon = shift @exons) {
    if ($found_start && !$found_end) {
      my $len = $exon->end - $exon->start + 1;

      my $endphase = ($len + $phase) % 3;
      $exon->phase($phase);
      $exon->end_phase($endphase);
      $phase = $endphase;
    }

    my $end = $start + $exon->length - 1;

    if ($cds_start >= $start && $cds_start <= $end) {
      $translation->start_Exon($exon);
      $translation->start($cds_start - $start + 1);
      $found_start = 1;
      my $len      = $end - $cds_start + 1;
      my $endphase = ($len + $phase) % 3;
      $exon->phase($phase);
      $exon->end_phase($endphase);
      $phase = $endphase;
    }

    if ($cds_end >= $start && $cds_end <= $end) {

      $translation->end_Exon($exon);
      $translation->end($cds_end - $start + 1);
      $found_end = 1;
    }
    $start += $exon->length;
  }

  if ($found_start == 0) {
    print STDERR
      "ERROR: Didn't find exon for start at $cds_start in CDS in exons:\n";
    my @exons = @{ $tran->get_all_Exons };
    foreach my $exon (@exons) {
      print STDERR "  Exon " . $exon->start . " " . $exon->end . "\n";
    }
  }

  if ($found_end == 0) {
    print STDERR
      "ERROR: Didn't find exon for end at $cds_end in CDS in exons:\n";
    my @exons = @{ $tran->get_all_Exons };
    foreach my $exon (@exons) {
      print STDERR "  Exon " . $exon->start . " " . $exon->end . "\n";
    }
  }
}

sub make_translation {
  my ($mrna, $cds_start, $cds_end, $start_phase) = @_;

  my $translation = new Bio::EnsEMBL::Translation;

  $mrna->translation($translation);

  my @exons = @{ $mrna->get_all_Exons };

  my $found_start = 0;
  my $found_end   = 0;
  my $phase       = $start_phase;

  if ($exons[0]->strand == 1) {

    foreach my $exon (@exons) {
      if ($found_start && !$found_end) {
        my $len      = $exon->end - $exon->start + 1;
        my $endphase = ($len + $phase) % 3;
        $exon->phase($phase);
        $exon->end_phase($endphase);
        $phase = $endphase;
      }

      if ($cds_start >= $exon->start && $cds_start <= $exon->end) {
        $translation->start_Exon($exon);
        $translation->start($cds_start - $exon->start + 1);
        $found_start = 1;
        my $len      = $exon->end - $cds_start + 1;
        my $endphase = ($len + $phase) % 3;
        $exon->phase(($cds_start == $exon->start) ? $phase : -1);
        $exon->end_phase($endphase);
        $phase = $endphase;
      }

      if ($cds_end >= $exon->start && $cds_end <= $exon->end) {
        $translation->end_Exon($exon);
        $translation->end($cds_end - $exon->start + 1);
        $found_end = 1;
        $exon->end_phase(($cds_end == $exon->end) ? 0 : -1);
      }
    }
  } else {

    foreach my $exon (@exons) {
      if ($found_start && !$found_end) {
        my $len      = $exon->end - $exon->start + 1;
        my $endphase = ($len + $phase) % 3;
        $exon->phase($phase);
        $exon->end_phase($endphase);
        $phase = $endphase;
      }

      if ($cds_start >= $exon->start && $cds_start <= $exon->end) {
        $translation->start_Exon($exon);
        $translation->start($exon->end - $cds_start + 1);

        $found_start = 1;
        my $len      = $cds_start - $exon->start + 1;
        my $endphase = ($len + $phase) % 3;
        $exon->phase(($cds_start == $exon->end) ? $phase : -1);
        $exon->end_phase($endphase);
        $phase = $endphase;
      }

      if ($cds_end >= $exon->start && $cds_end <= $exon->end) {
        $translation->end_Exon($exon);
        $translation->end($exon->end - $cds_end + 1);
        $found_end = 1;
      }
    }
  }

  if ($found_start == 0) {
    print STDERR "ERROR: Didn't find exon for start at $cds_start in exons:\n";
    foreach my $exon (@exons) {
      print STDERR "  Exon " . $exon->start . " " . $exon->end . "\n";
    }
  }

  if ($found_end == 0) {
    print STDERR "ERROR: Didn't find exon for end at $cds_end in exons:\n";
    foreach my $exon (@exons) {
      print STDERR "  Exon " . $exon->start . " " . $exon->end . "\n";
    }
  }
}

# From GeneBuilder (with added translation existence check)
sub prune_Exons {
  my ($gene) = @_;

  my @unique_Exons;

  # keep track of all unique exons found so far to avoid making duplicates
# need to be very careful about translation->start_exon and translation->end_Exon

  foreach my $tran (@{ $gene->get_all_Transcripts }) {
    my @newexons;
    foreach my $exon (@{ $tran->get_all_Exons }) {
      my $found;

      #always empty
      UNI: foreach my $uni (@unique_Exons) {
        if ($uni->start == $exon->start && $uni->end == $exon->end
          && $uni->strand == $exon->strand && $uni->phase == $exon->phase
          && $uni->end_phase == $exon->end_phase)
        {
          $found = $uni;
          last UNI;
        }
      }

      if (defined($found)) {
        push (@newexons, $found);
        if ($tran->translation) {
          if ($exon == $tran->translation->start_Exon) {
            $tran->translation->start_Exon($found);
          }

          if ($exon == $tran->translation->end_Exon) {
            $tran->translation->end_Exon($found);
          }
        }
      } else {
        push (@newexons,     $exon);
        push (@unique_Exons, $exon);
      }

    }
    $tran->flush_Exons;
    foreach my $exon (@newexons) {
      $tran->add_Exon($exon);
    }
  }
}

sub path_to_XML {
  my ($chr, $chrstart, $chrend, $type, @path) = @_;

  my %clones;
  my %versions;

  my $xmlstr;

  $xmlstr .= "  <assembly_type>" . $type . "<\/assembly_type>\n";

  @path = sort {$a->assembled_start <=> $b->assembled_start} @path;

  foreach my $p (@path) {
    $xmlstr .= "<sequencefragment>\n";

    $xmlstr .= "  <id>" . $p->component_Seq->id . "<\/id>\n";
    $xmlstr .= "  <chromosome>" . $chr . "<\/chromosome>\n";
    $xmlstr .= "  <assemblystart>" . ($chrstart + $p->assembled_start() - 1)
      . "<\/assemblystart>\n";
    $xmlstr .= "  <assemblyend>" . ($chrstart + $p->assembled_end() - 1)
      . "<\/assemblyend>\n";
    $xmlstr .= "  <assemblyori>" . $p->component_ori() . "<\/assemblyori>\n";
    $xmlstr .=
      "  <assemblyoffset>" . $p->component_start() . "<\/assemblyoffset>\n";

    $xmlstr .= "<\/sequencefragment>\n";

  }

  return $xmlstr;

}

sub genes_to_XML_with_Slice {
  my ($slice, $genes, $type, $writeseq) = @_;

  #print "Slice $slice\n";

  my @genes = @$genes;

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequenceset>\n";

  my @path  = @{ $slice->get_tiling_path };

  my $chr      = $slice->chr_name;
  my $chrstart = $slice->chr_start;
  my $chrend   = $slice->chr_end;

  $xmlstr .= Bio::Otter::Converter::path_to_XML($chr, $chrstart, $chrend, 
                                                $type, @path);

  if (defined($writeseq)) {
    $xmlstr .= "<dna>\n";
    my $seqstr = $slice->seq->seq;
    $seqstr =~ s/(.{72})/  $1\n/g;
    $xmlstr .= $seqstr . "\n";
    $xmlstr .= "</dna>\n";
  }

  foreach my $g (@genes) {
    foreach my $exon (@{$g->get_all_Exons}) {
      $exon->start($exon->start + $chrstart -1);
      $exon->end($exon->end + $chrstart -1);
    }
    $xmlstr .= $g->toXMLString . "\n";
    foreach my $exon (@{$g->get_all_Exons}) {
      $exon->start($exon->start - $chrstart + 1);
      $exon->end($exon->end - $chrstart + 1);
    }
  }

  $xmlstr .= "</sequenceset>\n";
  $xmlstr .= "</otter>\n";

  return $xmlstr;
}

sub slice_to_XML {
  my ($slice, $db, $writeseq) = @_;

  #print "Slice $slice : $db\n";

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequenceset>\n";

  my @path  = @{ $slice->get_tiling_path };
  #my @genes = @{ $db->get_AnnotatedGeneAdaptor->fetch_by_Slice($slice) };
  my @genes;

  if ($db->isa("Bio::Otter::DBSQL::DBAdaptor")) {
     @genes = @{ $db->get_AnnotatedGeneAdaptor->fetch_all_by_Slice($slice) };
   } else {
     my @tmpgenes = @{ $db->get_GeneAdaptor->fetch_all_by_Slice($slice) };
     foreach my $g (@tmpgenes) {
         my $ann = bless $g,"Bio::Otter::AnnotatedGene";
         my $ginfo = new Bio::Otter::GeneInfo;
         $ann->gene_info($ginfo);
         push(@genes,$ann);
         my @tran;

          foreach my $t (@{$g->get_all_Transcripts}) {
            if (defined($t->translation)) {
              print "Translate " . $t->stable_id . " " . $t->translate->seq . "\n";
              my $tr = $t->translation;
              print "Tran " . $tr->start_Exon->stable_id . " " . $tr->end_Exon->stable_id. " " . $tr->start . " " . $tr->end . "\n";

            foreach my $ex (@{$t->get_all_Exons}) {
               print $ex->stable_id . "\t" . $ex->gffstring . "\n";
            }
            }
            my $annt = bless $t, "Bio::Otter::AnnotatedTranscript";
            my $tinfo = new Bio::Otter::TranscriptInfo;
            if (defined($g->type)) {
               my $class = new Bio::Otter::TranscriptClass(-name => $g->type);
               $tinfo->class($class);
            }
 
            $annt->transcript_info($tinfo);
          }

      }

   }

  my $chr      = $slice->chr_name;
  my $chrstart = $slice->chr_start;
  my $chrend   = $slice->chr_end;

  $xmlstr .= Bio::Otter::Converter::path_to_XML($chr, $chrstart, $chrend, 
                                                $db->assembly_type, @path);

  if (defined($writeseq)) {
    $xmlstr .= "<dna>\n";
    my $seqstr = $slice->seq;
    $seqstr =~ s/(.{72})/  $1\n/g;
    $xmlstr .= $seqstr . "\n";
    $xmlstr .= "</dna>\n";
  }

  @genes = sort by_stable_id_or_name @genes;

  foreach my $g (@genes) {
    $xmlstr .= $g->toXMLString . "\n";
  }

  $xmlstr .= "</sequenceset>\n";
  $xmlstr .= "</otter>\n";

  return $xmlstr;
}


sub by_stable_id_or_name {

  my $astableid = "";
  my $bstableid = "";

  if (defined($a->stable_id)) {$astableid = $a->stable_id;}
  if (defined($b->stable_id)) {$bstableid = $b->stable_id;}
  
  my $cmpVal = ($astableid cmp $bstableid);

  if (!$cmpVal) {
    if (!defined($b->gene_info->name) && !defined($a->gene_info->name)) {
      $cmpVal = 0;
    } elsif (!defined($a->gene_info->name)) {
      $cmpVal = 1;
    } elsif (!defined($b->gene_info->name)) {
      $cmpVal = -1;
    } else {
      $cmpVal = ($a->gene_info->name cmp $b->gene_info->name);
    }
  }
  return $cmpVal;
}

# This isn't nice
# There is no way to create a slice (complete with sequence) 
# and then store it.  We have to create insert statements
# for the assembly and a

sub frags_to_slice {
  my ($chrname,$chrstart,$chrend,$assembly_type,$seqstr,$frags,$db) = @_;
 
   
  my %frags = %$frags;
  my $time = time;
  my $chrid;
  # if db then fetch the chromosome id

  my $chr = $db->get_ChromosomeAdaptor->fetch_by_chr_name($chrname);

  if (!defined($chr)) {
    print STDERR "Storing chromosome $chrname\n";
    my $chrsql = "insert into chromosome(chromosome_id,name) values(null,'$chrname')";
    my $sth    = $db->prepare($chrsql);
    my $res    = $sth->execute;

    $sth = $db->prepare("SELECT last_insert_id()");
    $sth->execute;

    ($chrid) = $sth->fetchrow_array;
    $sth->finish;
  } else {
    print STDERR "Using existing chromosome " . $chr->dbID . "\n";
    $chrid = $chr->dbID;
  }

  print STDERR "Chromosome id $chrid\n";

  foreach my $f (keys %frags) {
    
    if ($chrname eq "") {
      $chrname = $frags{$f}{chr};
    } elsif ($chrname ne $frags{$f}{chr}) {
      die " Chromosome names are different - can't make slice [$chrname][". $frags{$f}{chr} . "]\n";
    }
    
    my $fstart = $frags{$f}{start};
    my $fend   = $frags{$f}{end};
    my $fori   = $frags{$f}{strand};
    my $foff   = $frags{$f}{offset};

    if ($seqstr) {
    # Create clone

      my $clone = new Bio::EnsEMBL::Clone();
      $clone->id($f);
      $clone->embl_id($f);
      $clone->version(1);
      $clone->embl_version(1);
      $clone->htg_phase(-1);
      $clone->created($time);
      $clone->modified($time);
  
  
      # Create contig
  
      my $contig = new Bio::EnsEMBL::RawContig;
  
      $contig->name($f);
      $contig->clone($clone);
      $contig->embl_offset(1);
      $contig->length($fend-$fstart+$foff);
  
      my $subseq    = substr($seqstr,($fstart-$chrstart),($fend-$fstart+1));
  
      my $contigseq = new Bio::Seq(-seq => $subseq);
  
      if ($fstart == 9947971) {
        print "*****************************\n";
      }
      #print STDERR "Contigseq " . $contigseq->length . " " . length($seqstr) . " " . $fstart . " " . $fend . "\n";
  
      if ($fori == -1) {
        $contigseq = $contigseq->revcom;
      }
  
      my $padstr = 'N' x ($foff-1);
      
      #print STDERR "Foff [$foff-1]\n";
  
      my $newseq = $padstr . $contigseq->seq;
  
      #print STDERR "newseq " . length($newseq) ."\n";
  
      $contig->seq($newseq);
  
      $clone->add_Contig($contig);
  
      # Now store the clone
  
      $db->get_CloneAdaptor->store($clone);
    # Now for the assembly stuff
    } 

    my $contig = $db->get_RawContigAdaptor->fetch_by_name($f);
    my $rawid   = $contig->dbID;
    my $length  = ($fend-$fstart+1);
    my $raw_end = $foff + ($fend-$fstart);

    my $sqlstr = "insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values($chrid,$fstart,$fend,\'$f\',1,$length,1,$rawid,$foff,$raw_end,$fori,\'$assembly_type\')\n";

    #print "SQL $sqlstr\n";

    my $sth = $db->prepare($sqlstr);
    my $res = $sth->execute;

    $sth->finish;
    
    
  }
}

1;

