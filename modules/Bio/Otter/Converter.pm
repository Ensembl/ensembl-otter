package Bio::Otter::Converter;

use strict;
use Carp;

use Bio::Otter::Author;
use Bio::Otter::Keyword;
use Bio::Otter::AnnotatedGene;
use Bio::Otter::AnnotatedClone;
use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::CloneInfo;
use Bio::Otter::GeneInfo;
use Bio::Otter::Evidence;
use Bio::Otter::CloneRemark;
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

    confess "Not a filehandle" unless ref($fh) eq 'GLOB';

  my $gene = undef;
  my $tran;
  my $exon;
  my $author;
  my $geneinfo;
  my $traninfo;
  my $evidence;
  my $currentobj;
  my $seqstr        = undef;
  my $tl_start      = undef;
  my $tl_end        = undef;
  my $assembly_type = undef;
  my %frag;
  my $currfragname;
  my @genes;
  my $foundend = 0;
  my $time_now = time;
  my %clones;
  my @clones;
  my @cloneremarks;
  my @keywords;
  my @tiles;
  my $slice; 
  my $clone;
  my $version;

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
        #print STDERR "EEEK! Wrong locus type [$currentobj][$1]\n";
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
      } elsif ($currentobj eq 'frag') {
        push(@cloneremarks,$remark);
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

        #print STDERR  "Setting translation to $tl_start and $tl_end\n";

        my ($start_exon, $start_pos) = exon_pos($tran, $tl_start);
        my ($end_exon,   $end_pos)   = exon_pos($tran, $tl_end);

        if (!defined($start_exon) || !defined($end_exon)) {
          print "ERROR: Failed mapping translation to transcript\n";
        } else {
          #print STDERR "Translation id " . $tran->transcript_info->name . " " . $tran->stable_id . "\n";
          my $translation = new Bio::EnsEMBL::Translation;
          $translation->stable_id($tran->stable_id);
          $translation->version(1);
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

          if ($end_exon->length >= $end_pos) {
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
      $evidence->type('UNKNOWN');
      $traninfo->evidence($evidence);
      $currentobj = 'evidence';
    } elsif (/<\/evidence>/) {
      $currentobj = 'tran';
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
    } elsif (/<\/sequencefragment>/) {
       if (defined($clone) && defined($version)) {

         my $cloneobj = new Bio::Otter::AnnotatedClone;

         $cloneobj->id($clone);
         $cloneobj->embl_version($version);

         my $cloneinfo = new Bio::Otter::CloneInfo;

         my @keyobj;
         my @clonerem;

         foreach my $keyword (@keywords) {
           my $keyobj = new Bio::Otter::Keyword(-name => $keyword);
           push(@keyobj,$keyobj);
         }
         foreach my $remark (@cloneremarks) {
           my $remobj = new Bio::Otter::CloneRemark(-remark => $remark);
           push(@clonerem,$remobj);
         }
         $cloneinfo->remark(@clonerem);
         $cloneinfo->keyword(@keyobj);

         $cloneobj->clone_info($cloneinfo);

         $frag{$currfragname}{clone} = $cloneobj;

       }
       $clone = undef;
       $version = undef;

       @cloneremarks = ();
       @keywords     = ();

    } elsif (/<accession>(.*)<\/accession>/) {
      if ($currentobj eq 'frag') {
         $clone = $1;
      } else {
         die "ERROR: accession tag only allowed for sequence fragments.  Current obj is [$currentobj]\n";
      }
    } elsif (/<version>(.*)<\/version>/) {
      if ($currentobj eq 'frag') {
         $version = $1;
      } else {
         die "ERROR: version tag only allowed for sequence fragments.  Current obj is [$currentobj]\n";
      }

    } elsif (/<keyword>(.*)<\/keyword>/) {
      if ($currentobj ne 'frag') {
         die "ERROR: keyword tag only valid for sequence fragments";
      }
      push(@keywords,$1);
    } elsif (/<assembly_type>(.*)<\/assembly_type>/) {
      $assembly_type = $1;
    } elsif (/<assemblytype>(.*)<\/assemblytype>/) {
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
        if (length($seqstr)%1_000_000 < 100) {
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

    my $tile = new Bio::EnsEMBL::Tile();

    my $offset = $frag{$f}{offset};
    my $start  = $frag{$f}{start};
    my $end    = $frag{$f}{end};
    my $strand = $frag{$f}{strand};

    if (!defined($start)) {
       print "ERROR: No start defined for $f\n";
    }
    if (!defined($end)) {
       print "ERROR : No end defined for $f\n";
    }
    if (!defined($strand)) {
       print "ERROR : No strand defined for $f\n";
    }
    if (!defined($offset)) {
       print "ERROR : No offset defined for $f\n";
    }
    # print STDERR "START $f:$start:$end:$offset:$strand\n";

    $tile->assembled_start($start);
    $tile->assembled_end($end);
    $tile->component_ori($strand);
    $tile->component_start($offset);
    $tile->component_end($offset + $end - $start);
   
    my $contig = new Bio::EnsEMBL::RawContig();

    $contig->name($f);
    $contig->clone($frag{$f}{clone});

    $tile->component_Seq($contig);

   push(@tiles,$tile);
        
  }
  
  #$assembly_type = 'fake_gp_1' if (!defined($assembly_type));

  $slice = new Bio::EnsEMBL::Slice(-chr_name  => $chrname,
                                   -chr_start => $chrstart,
                                   -chr_end   => $chrend,
                                   -strand    => 1,
                                   -assembly_type => $assembly_type);


  #$slice->seq($seqstr);

  @fragnames = sort { $frag{$a}{start} <=> $frag{$b}{start} } @fragnames;
  @tiles     = sort { $a->assembled_start <=> $b->assembled_start} @tiles;

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

  #return (\@genes, \@clones,$chrname, $chrstart, $chrend,$assembly_type,$seqstr,);
  return (\@genes, $slice,$seqstr,\@tiles);
}

sub otter_to_ace {
  my ($contig, $genes, $path, $seq) = @_;
  
  my $str =  "\n\nSequence : \"" . $contig->display_id . "\"\nGenomic_canonical\n";

  my @path;

  if (defined($path)) {
     @path = @$path;
  }

  if ($contig->isa("Bio::EnsEMBL::Slice")) {
    my $slice = $contig;

    $str .= sprintf qq{Assembly_name "%s"\n}, $contig->assembly_type;

    if (!(@path)) {
      @path = @{$slice->get_tiling_path};
    }

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
        $str .= sprintf qq{Feature TilePath %d %d %f "%s"\n}, $start, $end, 1, $path->component_Seq->name;
    }
    foreach my $path (@path) {
        my $start;
        my $end;

        if ($path->component_ori == 1) {
          $start = $path->assembled_start;
          $end   = $path->assembled_end;
        } else {
          $end   = $path->assembled_start ;
          $start = $path->assembled_end;
        }
        $str .= sprintf qq{SubSequence "%s" %d %d\n}, 
                      $path->component_Seq->name, $start, $end;
    }
  }

  foreach my $gene (@$genes) {
  
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
      my $tran_name;

      if ($tran->transcript_info->name) {
        $tran_name = $tran->transcript_info->name;
      } else {
        $tran_name = $tran->stable_id;
      }

      $str .= "Subsequence   \"" . $tran_name . "\" ";

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

  $str .= "\n";


  #Clone features, keywords
  if ($contig->isa("Bio::EnsEMBL::Slice")) {
    my $slice = $contig;

    if (!(@path)) {
      @path  = @{ $slice->get_tiling_path };
    }
  }
    foreach my $path (@path) {
       my $clone = $path->component_Seq->clone; 
       $str .= "Sequence : \"". $clone->id . "." . $clone->embl_version . "\"\n";
       $str .= "Source " . $contig->display_id . "\n";

       my $clone_info = $clone->clone_info;
       foreach my $keyword ($clone_info->keyword) {
         $str .= "Keyword \"" . $keyword->name . "\"\n";
       }
       foreach my $remark ($clone_info->remark) {
         if ($remark->remark =~ /^Annotation_remark- /) {
           my $rem = $remark->remark;
           $rem =~ s/^Annotation_remark- //;
           $str .= "Annotation_remark \"" . ace_escape($rem) . "\"\n";
         } elsif ($remark->remark =~ /^EMBL_dump_info.DE_line- /) {
           my $rem = $remark->remark;
           $rem =~ s/^EMBL_dump_info.DE_line- //;
           $str .= "EMBL_dump_info DE_line \"" . ace_escape($rem) . "\"\n";
         } else {
           $str .= "Annotation_remark \"" . ace_escape($remark->remark) . "\"\n";
         }
       }
       if (defined($path->component_Seq->adaptor)) {
       foreach my $sf (@{$path->component_Seq->get_all_SimpleFeatures}) {
          my( $start, $end );
          if ($sf->strand == 1) {
              ($start, $end) = ($sf->start, $sf->end);
          } else {
              ($start, $end) = ($sf->end, $sf->start);
          }
          $str .= sprintf qq{Feature "%s" %d %d %f "%s"\n}, $sf->analysis->logic_name, $start, $end, $sf->score, $sf->display_label;
       } 
       }
       $str .= "\n";
    } 

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
      my $gene_name;
      if ($gene->gene_info->name && $gene->gene_info->name->name) {
        $gene_name = $gene->gene_info->name->name;
      } else {
        $gene_name = $gene->stable_id;
      }

      foreach my $tran (@{ $gene->get_all_Transcripts }) {
        my $tran_name;
        if ($tran->transcript_info->name) {
          $tran_name = $tran->transcript_info->name;
        } else {
          $tran_name = $tran->stable_id;
        }

        $str .= "Sequence : \"" . $tran_name . "\"\n";
        $str .= "Otter_id \"" . $tran->stable_id . "\"\n";
        $str .= "Source \"" . $contig->display_id . "\"\n";
        $str .= "Locus \"" . $gene_name . "\"\n";

        my $method = $tran->transcript_info->class->name;
        $str .= "Method \"" . $method . "\"\n";

        # Extra tags needed by ace
        if ($method =~ /supported_mRNA/) {
          $str .= "Processed_mRNA\n";
        } elsif ($method eq "Pseudogene") {
          $str .= "Pseudogene\nCDS\n";
        }

        my @remarks = $tran->transcript_info->remark;

        @remarks = sort {$a->remark cmp $b->remark} @remarks;

        foreach my $remark (@remarks) {
          if ($remark->remark =~ /^Annotation_remark- /) {
            my $rem = $remark->remark;
            $rem =~ s/^Annotation_remark- //;
            $str .= "Annotation_remark \"" . ace_escape($rem) . "\"\n";
          } else {
            $str .= "Remark \"" . ace_escape($remark->remark) . "\"\n";
          }
        }

        my @ev = $tran->transcript_info->evidence;

        @ev = sort {$a->name cmp $b->name} @ev;

        foreach my $ev (@ev) {
        if ($ev->db_name and exists($dbhash{$ev->db_name})) {
          $str .= $ev_types{ $ev->type } . " \"" . $dbhash{ $ev->db_name } . ":"
            . $ev->name . "\"\n";
        } else {
          $str .= $ev_types{ $ev->type } . " \"" . $ev->name . "\"\n";
        }
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
            $str .= sprintf qq{Source_Exons %d %d "%s"\n},
                $exon->start - $trans_off,
                $exon->end   - $trans_off,
                $exon->stable_id;
        } else {
            $str .= sprintf qq{Source_Exons %d %d "%s"\n},
                $trans_off - $exon->end,
                $trans_off - $exon->start,
                $exon->stable_id;
        }
      }

      # Seems to always be there - que?
      $str .= "Predicted_gene\n";

      if ($tran->translation) {
        my $translation = $tran->translation;

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
    my $gene_name;
    if ($gene->gene_info->name && $gene->gene_info->name->name) {
      $gene_name = $gene->gene_info->name->name;
    } else {
      $gene_name = $gene->stable_id;
    }

    $str .= "Locus : \"" . $gene_name . "\"\n";
    foreach my $synonym ($gene->gene_info->synonym) {
      $str .= "Alias \"" . $synonym->name . "\"\n";
    }

    #Need to add type here
    if (defined($gene->type)) {
      $str .= $gene->type . "\n";
    }
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
      my $tran_name;
      if ($tran->transcript_info->name) {
        $tran_name = $tran->transcript_info->name;
      } else {
        $tran_name = $tran->stable_id;
      }
      $str .= "Positive_sequence  \"" . $tran->transcript_info->name . "\"\n";
    }
    $str .= "Otter_id \"" . $gene->stable_id . "\"\n";
    $str .= "\n";
  }

  # Finally the dna
  $str .= "\nDNA \"" . $contig->display_id . "\"\n";

  while ($seq =~ /(.{1,72})/g) {
    $str .= $1 . "\n";
  }
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

# Setup regular expression components for parsing ace file format
my $OBJ_NAME  = qr/[\s:]+"?([^"]+)"?/;
my $STRING    = qr/\s+"?([^"]+)"?/;
my $INT       = qr/\s+(\d+)/;
my $FLOAT     = qr/\s+([\d\.]+)/;

sub ace_to_otter {
  my ($fh) = shift;

  my %sequence;

  my $currtran;
  my $contig;

  my @tran;
  my %genes;
  my %genenames;
  my $type;
  my %frags;
  my $chr;
  my $chrstart;
  my $chrend;
  my $dna;
  my $slice;
  my @tiles;

  while (<$fh>) {
    chomp;

    if (/^Sequence $OBJ_NAME/x) {
      my $currname = $1;
      print STDERR "Found sequence [$currname]\n";

      while (($_ = <$fh>) !~ /^\n$/) {
        chomp;

        if (/^Subsequence $STRING $INT $INT/x) {
          my $name  = $1;
          my $start = $2;
          my $end   = $3;

          print STDERR "Name $name $start $end\n";

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

        } elsif (/Assembly_name $STRING/x) {
          $type = $1;
        } elsif (/TilePath"? $INT $INT $STRING $STRING/x) {
          # TilePath is part of a feature line
          my $assstart  = $1;
          my $assend    = $2;
          my $assname   = $4;

          # Hmm - no offset
          if (defined($frags{$assname})) {
             print "ERROR: Fragment name [$assname] appears more than once in the tiling path\n";
          }
          $frags{$assname}{start} = $assstart;
          $frags{$assname}{end}   = $assend;
          $frags{$assname}{offset} = 1;  # SHOULD BE SET

        } elsif (/^Genomic_canonical/) {
          if ($currname =~ /(\S+).(\d+)-(\d+)/) {
             $chr      = $1;
             $chrstart = $2;
             $chrend   = $3;
          } else {
            print "Warning: Genomic_canonical sequence is not in the 6.1-10000 format [$currname].  Can't convert to chr, start,end\n";
          }
          #print "Found contig\n";

          if (defined($contig)) {
            die "Only one Genomic_canonical sequence allowed\n";
          }

          $contig = new Bio::EnsEMBL::RawContig;
          $contig->name($currname);

        } elsif (/^(Clone_right_end|Clone_left_end) $STRING $INT/x) {

          $sequence{$currname}{$1}{$2} = $3;

        } elsif (/^Keyword $STRING/x) {

          my $keywords = $sequence{$currname}{keyword} ||= [];
          push @$keywords, $1;

        } elsif (/^EMBL_dump_info\s+DE_line $STRING/x) {

          $sequence{$currname}{EMBL_dump_info} = $1;

        } elsif (/^Feature $STRING $INT $INT $FLOAT $STRING/x) {

          my $val   = $1;
          my $start = $2;
          my $end   = $3;
          my $score = $4;
          my $val2  = $5;

          # strand
          my $f = new Bio::EnsEMBL::SeqFeature(
            -name       => $val,
            -start      => $start,
            -end        => $end,
            -score      => $score,
            -gff_source => $val2
          );

          my $features = $sequence{$currname}{feature} ||= [];
          push @$features, $f;

        } elsif (/^Source $STRING/x) {

          # We have a gene and not a contig.
          $sequence{$currname}{Source} = $1;

          my $tran = new Bio::EnsEMBL::Transcript();
          $sequence{$currname}{transcript} = $tran;

          #print STDERR "new tran  $currname [$tran][$val]\n";
        } elsif (/^Source_Exons $INT $INT $STRING/x) {
          my $oldstart = $1;
          my $oldend   = $2;
          my $stableid = $3;

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

          print "Adding exon at $start $end to $currname\n";
          my $exon = new Bio::EnsEMBL::Exon(
            -start  => $start,
            -end    => $end,
            -strand => $tstrand
          );
          $exon->stable_id($stableid);

          $sequence{$currname}{transcript}->add_Exon($exon);

        } elsif (/^Continues_as $STRING/x) {

          $sequence{$currname}{Continues_as} = $1;

        } elsif (/^(cDNA_match|Protein_match|Genomic_match|EST_match) $STRING/x) {

          my $matches = $sequence{$currname}{$1} ||= [];
          push @$matches, $2;

        } elsif (/^Locus $STRING/x) {

          $genenames{$currname} = $1;

        } elsif (/^(Remark|Isoform|Predicted_gene) $STRING/x) {

          my $remarks = $sequence{$currname}{$1} ||= [];
          push @$remarks, $2;

        } elsif (/^CDS $INT $INT/x) {

          $sequence{$currname}{CDS_start} = $1;
          $sequence{$currname}{CDS_end}   = $2;

        } elsif (/^End_not_found/) {

          $sequence{$currname}{End_not_found} = 0;

        } elsif (/^Start_not_found $INT/x) {

          #print "start not found with $1\n";    
          $sequence{$currname}{Start_not_found} = $1;

        } elsif (/^Start_not_found/) {

          $sequence{$currname}{Start_not_found} = 0;

        } elsif (/^Method $STRING/x) {

          $sequence{$currname}{Method} = $1;

        } elsif (/^(Processed_mRNA|Pseudogene)/) {

          $sequence{$currname}{$1} = 1;

        }
      }
    } elsif (/^DNA $OBJ_NAME/x) {
      my $name = $1;
      my $seq;
      my $line;

      while (defined($fh) && ($line = <$fh>) && $line !~ /^\n$/) {
        chomp($line);
        $seq .= $line;
      }
      $dna = $seq;
    } elsif (/^Locus $OBJ_NAME/x) {
      my $name = $1;

      while (($_ = <$fh>) !~ /^\n$/) {
        if (/^Known/) {
          $genes{$name}{GeneType} = "Known";
        } elsif (/^Putative/) {
          $genes{$name}{GeneType} = "Putative";
        } elsif (/^Pseudogene/) {
          $genes{$name}{GeneType} = "Pseudogene";
        } elsif (/^Organism_supported/) {
          $genes{$name}{GeneType} = "Organism_supported";
        } elsif (/^Positive_sequence $STRING/x) {
          my $tranname = $1;

          if (!defined($genes{$name}{transcripts})) {
            $genes{$name}{transcripts} = [];
          }
          push (@{ $genes{$name}{transcripts} }, $tranname);
        } elsif (/^Otter_id $STRING/x) {
            $genes{$name}{StableID} = $1;
        }
      }
    }
  }

  #print "Contig pog $contig\n";
  my $contig_name = "";

  if (defined($contig->name)) { $contig_name = $contig->name; }

  #print "Name " . $contig_name . "\n";

  my %anntran;

  SEQ: foreach my $seq (keys %sequence) {
    my $transcript = $sequence{$seq}{transcript} or next SEQ;
    next SEQ unless @{$transcript->get_all_Exons};
    print STDERR "Seq = $seq\n";

    my $source = $sequence{$seq}{Source};
    print STDERR "Key $seq  $source  $contig_name\n";
    next SEQ unless $source and $source eq $contig_name;

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
      "SW" => "SWISSPROT",
      "TR" => "protein_id",
      "WP" => "protein_id",
    );

    foreach my $type (qw{ EST cDNA Protein Genomic }) {
      my $match_type = "${type}_match";
      if (my $ev_array = $sequence{$seq}{$match_type}) {

        foreach my $ev (@$ev_array) {
          my ($db_abbrev, $name) = split /:/, $ev;

          my $db_name = $dbhash{uc $db_abbrev};

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
      print ("Anntran $seq [$anntran]\n");
      die "No exons in transcript" unless @{$anntran->get_all_Exons};
      $anntran->sort;

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

        $translation->stable_id($tran->stable_id);
        $translation->version(1);

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
  return \@genes,\%frags,$type,$dna,$chr,$chrstart,$chrend;
}

sub ace_to_XML {
    my( $fh ) = @_;
    
    my( $genes, $frags, $type, $dna, $chr, $chrstart, $chrend) = ace_to_otter($fh);
    my $xml = "<otter>\n" . frags_to_XML($frags, $type, $chr, $chrstart, $chrend);
    foreach my $g (@$genes) {
        $xml .= $g->toXMLString;
    }
    $xml .= "\n</otter>\n";
    return $xml;
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
  $translation->stable_id($mrna->stable_id);
  $translation->version(1);
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

  #print STDERR "Pruning exons\n";

  my %exonhash;

  foreach my $tran (@{ $gene->get_all_Transcripts }) {
    my @newexons;
    foreach my $exon (@{$tran->get_all_Exons}) {
      my $found;
      #always empty

      UNI: foreach my $uni (@unique_Exons) {
        if ($uni->start  == $exon->start  && 
            $uni->end    == $exon->end    &&
            $uni->strand == $exon->strand && 
            $uni->phase  == $exon->phase   &&
            $uni->end_phase == $exon->end_phase)
        {
          $found = $uni;
          last UNI;
        }
      }
        print STDERR " Exon " . $exon->stable_id . "\n";
        print STDERR " Phase " . $exon->phase . " EndPhase " . $exon->end_phase . "\n";
        print STDERR " Strand " . $exon->strand . " Start " . $exon->start . " End ". $exon->end ."\n";

      if (defined($found)) {
        print STDERR " Duplicate\n";
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
        print STDERR "New = " . $exon->stable_id . "\n";

        ### This is nasty for the phases - sometimes exons come back with 
        ### the same stable id and different phases - we need to strip off
        ### the stable id if we think we have a new exon but we've
        ### already seen the stable_id

        if (defined($exon->stable_id) && defined($exonhash{$exon->stable_id})) {
           print STDERR "Already seen stable id " . $exon->stable_id . " - removing stable_id\n";
           $exon->{_stable_id} = undef;
           print STDERR "Exon id " .$exon->stable_id . "\n";
        }
        push (@newexons,     $exon);
        push (@unique_Exons, $exon);
      }
      $exonhash{$exon->stable_id} = 1;
    }
    $tran->flush_Exons;
    foreach my $exon (@newexons) {
      $tran->add_Exon($exon);
    }
  }

  my @exons = @{$gene->get_all_Exons};

  %exonhash = ();

  foreach my $ex (@exons) {
      $exonhash{$ex->stable_id}++;
  }

  foreach my $id (keys %exonhash) {
     if ($exonhash{$id} > 1) {
      print STDERR "Exon id seen twice $id " . $exonhash{$id} . "\n";
     }
   }
}

sub path_to_XML {
  my ($chr,$chrstart,$chrend,$type,$path) = @_;

  my @path   = @$path;

  my $xmlstr;

  $xmlstr .= "  <assembly_type>" . $type . "<\/assembly_type>\n";

  @path = sort {$a->assembled_start <=> $b->assembled_start} @path;

  foreach my $p (@path) {
    $xmlstr .= "<sequencefragment>\n";
    $xmlstr .= "  <id>" . $p->component_Seq->id . "<\/id>\n";
    $xmlstr .= "  <chromosome>" . $chr . "<\/chromosome>\n";

    if (defined($p->component_Seq->clone)) {
        my $clone = $p->component_Seq->clone;
        $xmlstr .= Bio::Otter::Converter::clone_to_XML($clone);
    }

    $xmlstr .= "  <assemblystart>" . ($chrstart + $p->assembled_start() - 1) . "<\/assemblystart>\n";
    $xmlstr .= "  <assemblyend>" . ($chrstart + $p->assembled_end() - 1) . "<\/assemblyend>\n";
    $xmlstr .= "  <assemblyori>" . $p->component_ori() . "<\/assemblyori>\n";
    $xmlstr .= "  <assemblyoffset>" . $p->component_start() . "<\/assemblyoffset>\n";
    $xmlstr .= "<\/sequencefragment>\n";
  }

  return $xmlstr;

}

sub clone_to_XML {
  my ($clone) = @_;

  if (!defined($clone)) {
     die "ERROR: clone needs to be entered to clone_to_XML\n";
  }
  my $str = "";

  $str .= "  <accession>" . $clone->id . "<\/accession>\n";
  $str .= "  <version>" . $clone->embl_version . "<\/version>\n";

  if ($clone->isa("Bio::Otter::AnnotatedClone") && defined($clone->clone_info)) {
     
     my @rem = $clone->clone_info->remark;
     my @key = $clone->clone_info->keyword;

     @rem = sort {$a->remark cmp $b->remark} @rem;
     @key = sort {$a->name   cmp $b->name  } @key;

     foreach my $rem (@rem) {
        $rem =~ s/\n/ /g;
        $str .= "  <remark>" . $rem->remark . "<\/remark>\n";
     }
     foreach my $key (@key) {
        $str .= "  <keyword>" . $key->name . "<\/keyword>\n";
     }
   }
   return $str;
}
sub frags_to_XML {
  my ($frags,$type,$chr,$start,$end) = @_;

  my $str = "  <assembly_type>" . $type . "<\/assembly_type>\n";

  my @names = keys %$frags;
  @names = sort {$frags->{$a}{start} <=> $frags->{$b}{start}} @names;

  foreach my $name (@names) {
     $str .= "    <sequencefragment>\n";
     $str .= "      <id>" . $name . "<\/id>\n";
     $str .= "      <chromosome>" . $chr . "<\/chromosome>\n";

     my $start = $frags->{$name}{start};
     my $end   = $frags->{$name}{end};

     if ($start < $end) {
     $str .= "      <assemblystart>" . $start . "<\/assemblystart>\n";
     $str .= "      <assemblyend>" . $end . "<\/assemblyend>\n";
     $str .= "      <assemblyori>1<\/assemblyori>\n";
     } else {
     $str .= "      <assemblystart>" . $end . "<\/assemblystart>\n";
     $str .= "      <assemblyend>" . $start . "<\/assemblyend>\n";
     $str .= "      <assemblyori>-1<\/assemblyori>\n";
     }
  }
  return $str;
}

sub genes_to_XML_with_Slice {
  my ($slice, $genes, $writeseq,$path,$seqstr) = @_;

  my @genes = @$genes;

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequenceset>\n";

  my @path;

  if (!defined($path)) {
    @path  = @{ $slice->get_tiling_path };
  } else {
    @path  = @$path;
  }
  my $chr      = $slice->chr_name;
  my $chrstart = $slice->chr_start;
  my $chrend   = $slice->chr_end;

  $xmlstr .= Bio::Otter::Converter::path_to_XML($chr, $chrstart, $chrend, 
                                                $slice->assembly_type, \@path);
  #print "XML $xmlstr\n";  

  print "Writeseq $writeseq\n";
  if ($writeseq && defined($slice->adaptor)) {
    $xmlstr .= "<dna>\n";
    $seqstr = $slice->seq unless $seqstr;
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
     @genes = @{ $db->get_AnnotatedGeneAdaptor->fetch_by_Slice($slice) };
   } else {
     my $tmpgenes = $db->get_GeneAdaptor->fetch_all_by_Slice($slice);
     foreach my $g (@$tmpgenes) {
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
                                                $db->assembly_type, \@path);

  if (defined($writeseq)) {
    $xmlstr .= "<dna>\n";
    my $seqstr = $slice->seq;
    $seqstr =~ s/(.{72})/  $1\n/g;
    $xmlstr .= $seqstr . "\n";
    $xmlstr .= "</dna>\n";
  }

  @genes = sort by_stable_id_or_name @genes;

  my %genehash;

  foreach my $g (@genes) {
    #print STDERR "Gene type " . $g->type . "\n";
    if ($g->type ne 'obsolete') {
    if (!defined($genehash{$g->stable_id})) {
       $genehash{$g->stable_id} = $g;
    } else {
      if ($g->version > $genehash{$g->stable_id}->version) {
         $genehash{$g->stable_id} = $g;
      }
    }
    }
  }
  foreach my $g (values %genehash) {
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
    #print STDERR "Storing chromosome $chrname\n";
    my $chrsql = "insert into chromosome(chromosome_id,name) values(null,'$chrname')";
    my $sth    = $db->prepare($chrsql);
    my $res    = $sth->execute;

    $sth = $db->prepare("SELECT last_insert_id()");
    $sth->execute;

    ($chrid) = $sth->fetchrow_array;
    $sth->finish;
  } else {
    #print STDERR "Using existing chromosome " . $chr->dbID . "\n";
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

sub ace_escape {
    my $str = shift;
    
    $str =~ s/\s+$//;       # Trim trailing whitespace.
    $str =~ s/\n/\\n/g;     # Backslash escape newlines
    $str =~ s/\t/\\t/g;     # and tabs.

    # Escape quotes, back and forward slashes,
    # % signs, and semi-colons.
    $str =~ s/([\/"%;\\])/\\$1/g;

    return $str;
}

1;

