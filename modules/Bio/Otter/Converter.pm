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


### Add authors to clones in XML_to_otter

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
  my $tl_stable_id  = undef;
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
      $gene->type($1);
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
      } else {
        print "ERROR: Current obj is $currentobj -can only add stable ids to gene,tran,exon\n";
      }
    }
    
    elsif (/<known>(.*)<\/known>/) {
        $geneinfo->is_known($1);
    }
    
    elsif (/<remark>(.*)<\/remark>/) {
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
        print "ERROR: Current obj is $currentobj -can only add remarks to gene, transcript or sequence_fragment\n";
      }
    }
    elsif (/<translation_start>(.*)<\/translation_start>/) {
      $tl_start = $1;

      if ($currentobj eq 'tran') {
      } else {
        print "ERROR: Current obj is $currentobj -can only add translation start to tran\n";
      }
    }
    elsif (/<translation_end>(.*)<\/translation_end>/) {
      $tl_end = $1;

      if ($currentobj eq 'tran') {
      } else {
        print "ERROR: Current obj is $currentobj -can only add translation end to tran\n";
      }
    }
    elsif (/<translation_stable_id>(.*)<\/translation_stable_id>/) {
        $tl_stable_id = $1;
    }
    elsif (/<author>(.*)<\/author>/) {
      $author->name($1);
    } elsif (/<author_email>(.*)<\/author_email>/) {
      $author->email($1);
    } elsif (/<dna>/) {
      # print STDERR "Found dna\n";
      if (defined($seqstr)) {
        die "ERROR: Got more than one dna record\n";
      } 
      $currentobj = 'dna';
    } elsif (/<transcript>/) {

      $tran     = new Bio::Otter::AnnotatedTranscript;
      $traninfo = new Bio::Otter::TranscriptInfo;
      $author   = Bio::Otter::Author->new;

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
          $translation->stable_id($tl_stable_id);
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
        print STDERR "ERROR: Either translation start or translation end undefined\n";
      }
      $tl_start     = undef;
      $tl_end       = undef;
      $tl_stable_id = undef;
    } elsif (/<cds_start_not_found>(.*)<\/cds_start_not_found>/) {
        $traninfo->cds_start_not_found($1);
    } elsif (/<cds_end_not_found>(.*)<\/cds_end_not_found>/) {
        $traninfo->cds_end_not_found($1);
    } elsif (/<mRNA_start_not_found>(.*)<\/mRNA_start_not_found>/) {
        $traninfo->mRNA_start_not_found($1);
    } elsif (/<mRNA_end_not_found>(.*)<\/mRNA_end_not_found>/) {
        $traninfo->mRNA_end_not_found($1);
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
        die "ERROR: name tag only associated with evidence, transcript or gene - obj is $currentobj\n";
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
    } elsif (/<sequence_fragment>/) {
      $currentobj = 'frag';
      $author = Bio::Otter::Author->new;
    } elsif (/<\/sequence_fragment>/) {
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
         $cloneinfo->author($author);

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
    } elsif (/<chromosome>(.*)<\/chromosome>/) {
      my $chr = $1;
      $frag{$currfragname}{chr} = $chr;
    } elsif (/<assembly_start>(.*)<\/assembly_start>/) {
      $frag{$currfragname}{start} = $1;
    } elsif (/<accession>(.*)<\/accession>/) {
      $currfragname = $1;

      if ($currentobj eq 'frag') {
        $frag{$currfragname}{id} = $1;
      }
    } elsif (/<assembly_end>(.*)<\/assembly_end>/) {
      $frag{$currfragname}{end} = $1;
    } elsif (/<fragment_ori>(.*)<\/fragment_ori>/) {
      $frag{$currfragname}{strand} = $1;
    } elsif (/<fragment_offset>(.*)<\/fragment_offset>/) {
      $frag{$currfragname}{offset} = $1;
    } elsif (/<.*?>.*<\/.*?>/) {
      print STDERR "ERROR: Unrecognised tag [$_]\n";
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
  
  ### End of XML parsing ###
  
  # Make the sequence fragments
  my @contigs;

  my $chrname  = "";
  my $chrstart = 2000000000;
  my $chrend   = -1;

  foreach my $f (keys %frag) {
    if ($chrname eq "") {
      $chrname = $frag{$f}{chr};
    } elsif ($chrname ne $frag{$f}{chr}) {
      print STDERR "fname = " . $f . "\n";
      print STDERR "frag id = " . $frag{$f}{id} . "\n";
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
       print STDERR "ERROR: No start defined for $f\n";
    }
    if (!defined($end)) {
       print STDERR "ERROR : No end defined for $f\n";
    }
    if (!defined($strand)) {
       print STDERR "ERROR : No strand defined for $f\n";
    }
    if (!defined($offset)) {
       print STDERR "ERROR : No offset defined for $f\n";
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

  @tiles     = sort { $a->assembled_start <=> $b->assembled_start} @tiles;

  # print STDERR "chrname = " . $chrname . " chrstart = " . $chrstart . " chrend = "
  #  . $chrend . "\n";

  # If we have a database connection, check that our tile path
  # is consistent with the assembly table in the database
  if (defined($db)) {
    if ($assembly_type) {
      $db->assembly_type($assembly_type);
    }
    my $sa    = $db->get_SliceAdaptor;
    $slice = $sa->fetch_by_chr_start_end($chrname, $chrstart, $chrend)
        or confess "Can't get slice for chr '$chrname' $chrstart-$chrend on $assembly_type";

    my $path = $slice->get_tiling_path;
  
    ## Only store slice if no tiling path returned
    ## Then refetch slice
    #
    #unless (@$path) {
    #  
    #  Bio::Otter::Converter::frags_to_slice($chrname,$chrstart,$chrend,$assembly_type,$seqstr,\%frag,$db);
    #  
    #  $sa    = $db->get_SliceAdaptor;
    #  $slice = $sa->fetch_by_chr_start_end($chrname, $chrstart, $chrend);
    #  
    #  $path = $slice->get_tiling_path;
    #}

    unless (@$path) {
        die "Can't get tiling path for chr '$chrname' $chrstart-$chrend on $assembly_type";
    }

    my @fragnames = sort { $frag{$a}{start} <=> $frag{$b}{start} } keys %frag;
    foreach my $tile (@$path) {
      my $fragname = shift @fragnames;
      if ($tile->component_Seq->name ne $fragname
        || ($slice->chr_start + $tile->assembled_start - 1) != $frag{$fragname}{start}
        || ($slice->chr_start + $tile->assembled_end   - 1) != $frag{$fragname}{end}
      ) {
        die "Assembly doesn't match for contig $fragname\n";
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

my %ace2ens_phase = (
    1   => 0,
    2   => 2,
    3   => 1,
    );

my %ens2ace_phase = (
    0   => 1,
    2   => 2,
    1   => 3,
    );

sub otter_to_ace {
    my ($slice, $genes, $path, $seq) = @_;

    my $slice_name = $slice->display_id;

    my $str =  qq{\n\nSequence : "$slice_name"\nGenomic_canonical\n};
    $str .= sprintf qq{Assembly_name "%s"\n}, $slice->assembly_type;

    unless (@$path) {
      $path = $slice->get_tiling_path;
    }

    my $chr      = $slice->chr_name;
    my $chrstart = $slice->chr_start;

    my( %authors );

    # Add SMap tags for assembly
    foreach my $tile (@$path) {
        my $start           = $tile->assembled_start - $chrstart + 1;
        my $end             = $tile->assembled_end   - $chrstart + 1;
        my $contig_start    = $tile->component_start;
        my $name            = $tile->component_Seq->name;

        if ($tile->component_ori == 1) {
            $str .= qq{AGP_Fragment "$name" $start $end Align $start $contig_start\n};
        } else {
            # Clone in reverse orientaton in AGP is indicated
            # to acedb by first coordinate > second
            $str .= qq{AGP_Fragment "$name" $end $start Align $end $contig_start\n};
        }
    }

    # add SubSequence coordinates to Genomic
    foreach my $gene (@$genes) {
        foreach my $tran (@{ $gene->get_all_Transcripts }) {

            $str .= sprintf qq{Subsequence "%s" },
                $tran->transcript_info->name || $tran->stable_id;

            $tran->sort;
            my $exons = $tran->get_all_Exons;

            if ($exons->[0]->strand == 1) {
                $str .= $tran->start . " " . $tran->end . "\n";
            } else {
                $str .= $tran->end . " " . $tran->start . "\n";
            }
        }
    }

    # Clone features, keywords
    foreach my $tile (@$path) {
        my $clone = $tile->component_Seq->clone;
        my $name  = $tile->component_Seq->name;
        my $accession  = $clone->id            or die "No embl_id on clone attached to '$name' in tile";
        my $sv         = $clone->embl_version  or die "No embl_version on clone attached to '$name' in tile";;
        my $clone_info = $clone->clone_info;
        $str .= qq{\nSequence : "$name"\nSource "$slice_name"\nAccession "$accession"\nSequence_version $sv\n};

        foreach my $keyword ($clone_info->keyword) {
            $str .= sprintf qq{Keyword "%s"\n}, ace_escape($keyword->name);
        }
        foreach my $remark ($clone_info->remark) {
            my $rem = ace_escape($remark->remark);
            if ($rem =~ s/^Annotation_remark- //) {
                $str .= qq{Annotation_remark "$rem"\n};
            }
            elsif ($rem =~ s/^EMBL_dump_info.DE_line- //) {
                $str .= qq{EMBL_dump_info DE_line "$rem"\n};
            }
            else {
                $str .= qq{Annotation_remark "$rem"\n};
            }
        }

        ### Do we need to get all features?    - Is it just for PolyA?
        if (defined($tile->component_Seq->adaptor)) {
            foreach my $sf (@{$tile->component_Seq->get_all_SimpleFeatures}) {
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

    # Add Sequence objects for Transcripts
    foreach my $gene (@$genes) {
        my $gene_name;
        if (my $gn = $gene->gene_info->name) {
            $gene_name = $gn->name;
        }
        $gene_name ||= $gene->stable_id;

        foreach my $tran (@{ $gene->get_all_Transcripts }) {
            my $tran_name = $tran->transcript_info->name || $tran->stable_id;

            $str .= "Sequence : \"" . $tran_name . "\"\n";
            $str .= "Transcript_id \"" . $tran->stable_id . "\"\n";
            $str .= "Source \"" . $slice->display_id . "\"\n";
            $str .= "Locus \"" . $gene_name . "\"\n";
            if (my $author = $tran->transcript_info->author) {
                my $name  = $author->name;
                # author has a unique key in the database
                $authors{$author->email} ||= $author;
                $str .= qq{Transcript_author "$name"\n};
            }

            my $method = $tran->transcript_info->class->name;
            $str .= "Method \"" . $method . "\"\n";

            # Extra tags needed by ace
            if ($method =~ /supported_mRNA/) {
                $str .= "Processed_mRNA\n";     ### check this
            } elsif ($method eq "Pseudogene") {
                $str .= "Pseudogene\nCDS\n";
            }

            my @remarks = $tran->transcript_info->remark;
            foreach my $remark (sort map $_->remark, @remarks) {
                if ($remark =~ s/^Annotation_remark- //) {
                    $str .= "Annotation_remark \"" . ace_escape($remark) . "\"\n";
                } else {
                    $str .= "Remark \"" . ace_escape($remark) . "\"\n";
                }
            }

            # Supporting evidence
            my @ev = sort {$a->name cmp $b->name} $tran->transcript_info->evidence;
            foreach my $ev (@ev) {
                my $type = $ev->type;
                my $name = $ev->name;
                $str .= qq{${type}_match "$name"\n};
            }

            my $trans_off;
            my $exons = $tran->get_all_Exons;

            my $strand = $exons->[0]->strand;
            if ($strand == 1) {
              $trans_off = $tran->start - 1;
              foreach my $exon (@$exons) {
                $str .= sprintf qq{Source_Exons %d %d "%s"\n},
                        $exon->start - $trans_off,
                        $exon->end   - $trans_off,
                        $exon->stable_id;
              }
            } else {
              $trans_off = $tran->end + 1;
              foreach my $exon (@$exons) {
                $str .= sprintf qq{Source_Exons %d %d "%s"\n},
                        $trans_off - $exon->end,
                        $trans_off - $exon->start,
                        $exon->stable_id;
              }
            }

            # Seems to always be there - que?
            $str .= "Predicted_gene\n";

            if (my $translation = $tran->translation) {
                $str .= sprintf qq{Translation_id "%s"\n}, $translation->stable_id;
                $str .= "CDS ";
                if ($strand == 1) {
                    $str .= rna_pos($tran, $tran->coding_region_start) . " ";
                    $str .= rna_pos($tran, $tran->coding_region_end) . "\n";
                } else {
                    $str .= rna_pos($tran, $tran->coding_region_end) . " ";
                    $str .= rna_pos($tran, $tran->coding_region_start) . "\n";
                }
            }

            my $info = $tran->transcript_info;
            if ($info->cds_start_not_found) {
                # Get start phase of first exon
                my $first_exon_phase = $exons->[0]->phase;
                my $ace_phase = $ens2ace_phase{$first_exon_phase};
                if ($ace_phase) {
                    $str .= "Start_not_found $ace_phase\n";
                } else {
                    warn "No ace phase for ensembl phase '$first_exon_phase' in '$tran_name'\n";
                    $str .= "Start_not_found\n";
                }
            }
            elsif ($info->mRNA_start_not_found) {
                $str .= "Start_not_found\n";
            }

            if ($info->cds_end_not_found   || $info->mRNA_end_not_found) {
                $str .= "End_not_found\n";
            }

            $str .= "\n";
        }
        $str .= "\n";
    }

    $str .= "\n";

    # Locus objects for genes
    foreach my $gene (@$genes) {
        my $info = $gene->gene_info;
        my $gene_name;
        if ($info->name && $info->name->name) {
            $gene_name = $info->name->name;
        } else {
            $gene_name = $gene->stable_id;
        }

        $str .= "Locus : \"" . $gene_name . "\"\n";
        foreach my $synonym ($info->synonym) {
            $str .= "Alias \"" . $synonym->name . "\"\n";
        }
        
        $str .= "Known\n" if $gene->is_known;

        if (my $author = $info->author) {
            my $name  = $author->name;
            # email has a unique key in the database
            $authors{$author->email} ||= $author;
            $str .= qq{Locus_author "$name"\n};
        }

        # We don't get type from the XML
        ## Add gene type
        #if (my $type = $gene->type) {
        #    ### Is this adequate?
        #    $str .= "$type\n";
        #}
        
        foreach my $tran (@{ $gene->get_all_Transcripts }) {
            my $tran_name;
            if ($tran->transcript_info->name) {
                $tran_name = $tran->transcript_info->name;
            } else {
                $tran_name = $tran->stable_id;
            }
            $str .= qq{Positive_sequence "$tran_name"\n};
        }
        $str .= "Locus_id \"" . $gene->stable_id . "\"\n";
        $str .= "\n";
    }

    foreach my $author (values %authors) {
        my $name = $author->name;
        my $email = $author->email;
        $str .= qq{\nPerson : "$name"\nEmail "$email"\n};
    }

    if ($seq) {
        # Finally the dna
        $str .= "\nDNA \"" . $slice->display_id . "\"\n";
        while ($seq =~ /(.{1,72})/g) {
            $str .= $1 . "\n";
        }
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

  #print STDERR "start = " . $start;
  #print STDERR " end = " . $end;
  #print STDERR " loc = " . $loc . "\n";

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
    #print STDERR "Exon " . $exon->stable_id . " " . $exon->start . "\t" . $exon->end . "\t" . $exon->strand . "\t" . $exon->phase . "\t" . $exon->end_phase. "\n";
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
  print STDERR "Returning undef\n";
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
my $OBJ_NAME  = qr/[\s:]+"?([^"\n]+)"?/;
my $STRING    = qr/\s+"?([^"\n]+)"?/;
my $INT       = qr/\s+(\d+)/;
my $FLOAT     = qr/\s+([\d\.]+)/;

sub ace_to_otter {
    my( $fh ) = @_;

    my(
        %sequence,      # Accumulates Sequence information keyed by sequence name
        %genes,         # Accumulates Locus information keyed by locus name
        %genenames,     # Links Sequence names to Locus names
        %authors,       # Bio::Otter::Author objects keyed by author name
        %frags,         # hashes used to capture genomic fragment tiling data
        $slice_name,    # Name of the parent Genomic sequence
        $assembly_type,
        $chr_name,
        $chr_start,
        $chr_end,
        $dna,
        );

    # Main parsing loop - might be more effecient to split on objects (ie: $/ = "")
    while (<$fh>) {

        # Parse Sequence object, which could be Genomic (slice) or SubSequence (transcript)
        if (/^Sequence $OBJ_NAME/x) {
            my $currname = $1;
            my $curr_seq = $sequence{$currname} ||= {};

            #print STDERR "Found sequence [$currname]\n";

            ### Could slightly optimize this loop by moving the more numerous lines nearer to the top
            while (($_ = <$fh>) !~ /^\n$/) {
                
                if (/^Subsequence $STRING $INT $INT/x) {
                    my $name  = $1;
                    my $start = $2;
                    my $end   = $3;

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
                }
                elsif (/Assembly_name $STRING/x) {
                    $assembly_type = $1;
                }

                # SMap assembly information is formatted like this:
                #
                #  AGP_Fragment "AL356489.14"      1 130539 Align      1  101
                #  AGP_Fragment "AL358573.25" 130540 143537 Align 130540 2001
                #  AGP_Fragment "AL139113.21" 143538 334817 Align 143538 2001
                #  AGP_Fragment "AL354989.13" 334818 484807 Align 334818 2001
                #  AGP_Fragment "AL160051.22" 484808 514439 Align 484808 1001
                #  AGP_Fragment "AL353662.19" 514440 680437 Align 514440 2001
                elsif (/^AGP_Fragment $STRING $INT $INT \s+Align $INT $INT/x) {
                    my $name   = $1;
                    my $start  = $2;
                    my $end    = $3;
                    # Don't need $4
                    my $offset = $5;

                    ### Not yet tested for reverse strand!
                    my $strand = 1;
                    if ($start > $end) {
                        $strand = -1;
                        ($start, $end) = ($end, $start);
                    }

                    $frags{$name} = {
                        start   => $start,
                        end     => $end,
                        offset  => $offset,
                        strand  => $strand,
                        }
                }

                elsif (/^Genomic_canonical/) {
                    if ($currname =~ /(\S+)\.(\d+)-(\d+)/) {
                        $chr_name  = $1;
                        $chr_start = $2;
                        $chr_end   = $3;
                    } else {
                       print STDERR "Warning: Genomic_canonical sequence is not in the 6.1-10000 format [$currname].  Can't convert to chr, start,end\n";
                    }
                    #print STDERR "Found contig\n";

                    if ($slice_name) {
                        die "Only one Genomic_canonical sequence allowed\n";
                    } else {
                        $slice_name = $currname;
                    }
                }
                elsif (/^(Keyword|Remark|Annotation_remark) $STRING/x) {
                  my $anno_txts = $curr_seq->{$1} ||= [];
                  push @$anno_txts, ace_unescape($2);
                }
                elsif (/^EMBL_dump_info\s+DE_line $STRING/x) {
                    $curr_seq->{EMBL_dump_info} = ace_unescape($1);
                }
                elsif (/^Feature $STRING $INT $INT $FLOAT $STRING/x) {
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

                    my $features = $curr_seq->{feature} ||= [];
                    push @$features, $f;
                }
                elsif (/^Source $STRING/x) {
                    # We have a gene and not a contig.
                    $curr_seq->{Source} = $1;

                    my $tran = Bio::Otter::AnnotatedTranscript->new;
                    $curr_seq->{transcript} = $tran;

                    #print STDERR "new tran  $currname [$tran][$val]\n";
                }
                elsif (/^Source_Exons $INT $INT (?:$STRING)?/x) {
                    my $oldstart = $1;
                    my $oldend   = $2;
                    my $stableid = $3;    # Will not always have a stable_id

                    my $tstart  = $curr_seq->{start};
                    my $tend    = $curr_seq->{end};
                    my $tstrand = $curr_seq->{strand};

                    my $start;
                    my $end;

                    if ($tstrand == 1) {
                        $start = $oldstart + $tstart - 1;
                        $end   = $oldend + $tstart - 1;
                    } else {
                        $end   = $tend - $oldstart + 1;
                        $start = $tend - $oldend + 1;
                    }

                    print STDERR "Adding exon at $start $end to $currname\n";
                    my $exon = new Bio::EnsEMBL::Exon(
                        -start  => $start,
                        -end    => $end,
                        -strand => $tstrand
                    );
                    $exon->stable_id($stableid);

                    ### This assumes the "Source" tag will always be encountered before Exon tags - bad
                    $curr_seq->{transcript}->add_Exon($exon);
                }
                elsif (/^(cDNA_match|Protein_match|Genomic_match|EST_match) $STRING/x) {
                    my $matches = $curr_seq->{$1} ||= [];
                    push @$matches, $2;
                }
                elsif (/^Locus $STRING/x) {
                    $genenames{$currname} = $1;
                }
                elsif (/^CDS $INT $INT/x) {
                    $curr_seq->{CDS_start} = $1;
                    $curr_seq->{CDS_end}   = $2;
                }
                elsif (/^End_not_found/) {
                    $curr_seq->{End_not_found} = 1;
                }
                elsif (/^Start_not_found $INT/x) {
                    #print STDERR "start not found with $1\n";
                    my $phase = $ace2ens_phase{$1};
                    die "Bad Start_not_found '$1'" unless defined($phase);
                    $curr_seq->{Start_not_found} = $1;
                }
                elsif (/^Start_not_found/) {
                    $curr_seq->{Start_not_found} = -1;
                }
                elsif (/^Method $STRING/x) {
                    $curr_seq->{Method} = $1;
                }
                elsif (/^(Processed_mRNA|Pseudogene)/) {
                    $curr_seq->{$1} = 1;
                }
                elsif (/^(Transcript_id|Translation_id|Transcript_author|Accession) $STRING/x) {
                    $curr_seq->{$1} = $2;
                }
                elsif (/^Sequence_version $INT/x) {
                    $curr_seq->{Sequence_version} = $1;
                }
            }
        }

        # Parse Locus objects
        elsif (/^Locus $OBJ_NAME/x) {
            my $name = $1;
            my $cur_gene = $genes{$name} ||= {};

            while (($_ = <$fh>) !~ /^\n$/) {

                ### Need to deal with polymorphic loci?
                if (/^(Known|Novel_(CDS|Transcript)|Putative|Pseudogene)/) {
                    $cur_gene->{GeneType} = $1;
                }
                elsif (/((P|Unp)rocessed)/) {
                    $cur_gene->{GeneType} = "Pseudogene-$1";
                }
                elsif (/^((Non_o|O)rganism_supported)/) {
                    $cur_gene->{GeneType} = "Novel_CDS-$1";
                }

                elsif (/^Positive_sequence $STRING/x) {
                    my $tran_list = $cur_gene->{transcripts} ||= [];
                    push @$tran_list, $1;
                }
                elsif (/^(Locus_(?:id|author)) $STRING/x) {
                    $cur_gene->{$1} = $2;
                }
                elsif (/^Remark $STRING/x) {
                    my $remark_list = $cur_gene->{remarks} ||= [];
                    push(@$remark_list, $1);
                }
                elsif (/^Alias $STRING/x) {
                    my $alias_list = $cur_gene->{aliases} ||= [];
                    push(@$alias_list, $1);
                }
            }
        }
        
        # Parse Person objects
        elsif (/^Person $OBJ_NAME/x) {
            warn "Found Person '$1'";
            my $author_name = $1;
            my( $author_email );
            while (($_ = <$fh>) !~ /^\n$/) {
                print STDERR "Person: $_";
                if (/^Email $STRING/x) {
                    $author_email = $1;
                }
            }
            
            unless ($author_email) {
                die "Missing Email tag in Person '$author_name'";
            }
            
            my $author = $authors{$author_name} = Bio::Otter::Author->new;
            $author->name($author_name);
            $author->email($author_email);
            #warn "Made '$author_name' $authors{$author_name}";
        }
    
        # Parse DNA objects
        elsif (/^DNA $OBJ_NAME/x) {
            my $name = $1;
            my $seq;
            my $line;

            while (defined($fh) && ($line = <$fh>) && $line !~ /^\n$/) {
                chomp($line);
                $seq .= $line;
            }
            $dna = $seq;
        }
    }

    #print STDERR "Slice is '$slice_name'\n";
    die "Failed to find name of slice" unless $slice_name;

    my %anntran;

    # Make transcripts and translations
    #SEQ: foreach my $seq (keys %sequence) {
    #    my $seq_data = $sequence{$seq};
    SEQ: while (my ($seq, $seq_data) = each %sequence) {
        my $transcript = $seq_data->{transcript} or next SEQ;
        next SEQ unless @{$transcript->get_all_Exons};
        print STDERR "Seq = $seq\n";

        my $source = $seq_data->{Source};
        print STDERR "Key $seq    $source    $slice_name\n";
        next SEQ unless $source and $source eq $slice_name;

        if (my $tsid = $seq_data->{Transcript_id}) {
            $transcript->stable_id($tsid);
        }

        my $traninfo = new Bio::Otter::TranscriptInfo;
        $traninfo->name($seq);
        if (my $au_name = $seq_data->{Transcript_author}) {
            my $author = $authors{$au_name} or die "No author object '$au_name'";
            $traninfo->author($author);
        }

        # Remarks
        if (my $rem_list = $seq_data->{Annotation_remark}) {
            foreach my $txt (@$rem_list) {
                my $remark = Bio::Otter::TranscriptRemark->new;
                # Method should be called "name" for symetry with CloneRemark
                $remark->remark("Annotation_remark- $txt");
                $traninfo->remark($remark);
            }
        }
        if (my $remark_list = $seq_data->{Remark}) {
            foreach my $rem (@$remark_list) {
                my $remark = Bio::Otter::TranscriptRemark->rem(-remark => $rem);
                $traninfo->remark($remark);
            }
        }

        # Evidence for the transcript
        my @evidence;
        foreach my $type (qw{ EST cDNA Protein Genomic }) {
            my $match_type = "${type}_match";
            if (my $ev_array = $seq_data->{$match_type}) {

                foreach my $name (@$ev_array) {
                    my $obj = new Bio::Otter::Evidence(
                        -type        => $type,
                        -name        => $name,
                        );

                    push (@evidence, $obj);
                }
            }
        }
        $traninfo->evidence(@evidence);

        # Type of transcript (Method tag)
        my $class = Bio::Otter::TranscriptClass
            ->new(-name => $seq_data->{Method});
        $traninfo->class($class);

        #print STDERR "Defined $seq " . $seq_data->{transcript} . "\n";
        if (my $anntran = $seq_data->{transcript}) {

            $anntran->transcript_info($traninfo);

            $anntran{$seq} = $anntran;

            # Sort the exons here just in case
            print STDERR "Anntran $seq [$anntran]\n";
            die "No exons in transcript '$seq'" unless @{$anntran->get_all_Exons};
            $anntran->sort;

            if ($seq_data->{CDS_start}) {                
                # Set the translation start and end
                my $cds_start = $seq_data->{CDS_start};
                my $cds_end   = $seq_data->{CDS_end};
                
                my $translation = Bio::EnsEMBL::Translation->new;
                $anntran->translation($translation);
                $translation->version(1);
                if (my $tsl_id = $seq_data->{Translation_id}) {
                    $translation->stable_id($tsl_id);
                }

                # Set the phase of the exons
                my $start_phase = $seq_data->{Start_not_found};
                if (defined $start_phase) {
                    $traninfo->mRNA_start_not_found(1);
                    $traninfo->cds_start_not_found(1) if $start_phase != -1;
                } else {
                    $start_phase = 0;
                }

                my $phase = -1;
                my $in_cds = 0;
                my $found_cds = 0;
                my $cds_pos = 0;
                #foreach my $exon (@{$anntran->get_all_Exons}) {
                my $exon_list = $anntran->get_all_Exons;
                for (my $i = 0; $i < @$exon_list; $i++) {
                    my $exon = $exon_list->[$i];
                    my $exon_start = $cds_pos + 1;
                    my $exon_end   = $cds_pos + $exon->length;
                    my $exon_cds_length = 0;
                    if ($in_cds) {
                        $exon_cds_length = $exon->length;
                        $exon->phase($phase);
                    }
                    elsif ($cds_start <= $exon_end) {
                        $in_cds    = 1;
                        $found_cds = 1;
                        $phase = $start_phase;

                        if ($cds_start > $exon_start) {
                            # beginning of exon is non-coding
                            $exon->phase(-1);
                        } else {
                            $exon->phase($phase);
                        }
                        $exon_cds_length = $exon_end - $cds_start + 1;
                        $translation->start_Exon($exon);
                        $translation->start($cds_start - $exon_start + 1);
                    }
                    else {
                        $exon->phase($phase);
                    }

                    my $end_phase = -1;
                    if ($in_cds) {
                        $end_phase = ($exon_cds_length + $phase) % 3;
                    }

                    if ($cds_end <= $exon_end) {
                        # Last translating exon
                        $in_cds = 0;
                        $translation->end_Exon($exon);
                        $translation->end($cds_end - $exon_start + 1);
                        if ($cds_end < $exon_end) {
                            $exon->end_phase(-1);
                        } else {
                            $exon->end_phase($end_phase);
                        }
                        $phase = -1;
                    } else {
                        $exon->end_phase($end_phase);
                        $phase = $end_phase;
                    }

                    $cds_pos = $exon_end;
                }
                $anntran->throw("Failed to find CDS in '$seq'") unless $found_cds;
                
                if ($seq_data->{End_not_found}) {
                    my $last_exon_end_phase = $exon_list->[$#$exon_list]->end_phase;
                    $traninfo->mRNA_end_not_found(1);
                    $traninfo->cds_end_not_found(1) if $last_exon_end_phase != -1;
                }
            } else {
                # No translation, so all exons get phase -1
                foreach my $exon (@{$anntran->get_all_Exons}) {
                    $exon->phase(-1);
                    $exon->end_phase(-1);
                }
                $traninfo->mRNA_start_not_found(1) if defined $seq_data->{Start_not_found};
                $traninfo->mRNA_end_not_found(1)   if defined $seq_data->{End_not_found};
            }
        }
    }

    # Fix exon coordinates
    {
        my $offset = $chr_start - 1;
        foreach my $transcript (values %anntran) {
            foreach my $exon (@{$transcript->get_all_Exons}) {
                #warn "got '$exon'\n";
                $exon->start($exon->start + $offset);
                $exon->end  ($exon->end   + $offset);
            }
        }
    }


    # Make gene objects
    my @genes;
    while (my ($gname, $gene_data) = each %genes) {
        print STDERR "Gene name = $gname\n";
        my $gene  = Bio::Otter::AnnotatedGene->new;
        my $ginfo = Bio::Otter::GeneInfo->new;
        $gene->gene_info($ginfo);
        
        if (my $type = $gene_data->{GeneType}) {
            $gene->type($type);
        } else {
            warn "No gene type for gene '$gname' - setting type to 'Gene'\n";
            $gene->type('Gene');
        }

        if (my $gsid = $gene_data->{Locus_id}) {
                $gene->stable_id($gsid);
        }
        if (my $au_name = $gene_data->{Locus_author}) {
                my $author = $authors{$au_name} || die "No author object '$au_name'";
                $ginfo->author($author);
        }
        
        # Names and aliases (synonyms)
        $ginfo->name(
            Bio::Otter::GeneName->new(
                -name => $gname,
            ));
        if (my $list = $gene_data->{aliases}) {
            foreach my $text (@$list) {
                my $synonym = Bio::Otter::GeneSynonym->new;
                $synonym->name($text);
                $ginfo->synonym($synonym);
            }
        }
        
        # Gene remarks
        if (my $list = $gene_data->{remarks}) {
            foreach my $text (@$list) {
                my $remark = Bio::Otter::GeneRemark->new;
                $remark->remark($text);
                $ginfo->remark($remark);
            }
        }

        print STDERR "Made gene $gname\n";

        push (@genes, $gene);

        # We need to pair up the CDS transcript objects with the 
        # mRNA objects and set the translations

        my @newtran;

        TRAN: foreach my $tranname (@{ $gene_data->{transcripts} }) {
            my $tran = $anntran{$tranname};
            my $tran_data = $sequence{$tranname};

            unless ($tran) {
                warn "Transcript '$tranname' in Locus '$gname' not found in ace data\n";
                next TRAN;
            }

            $gene->add_Transcript($tran);
        }

        prune_Exons($gene);
    }
    
    # Turn %frags into a Tiling Path
    my $tile_path = [];
    foreach my $ctg_name (keys %frags) {
        my $fragment = $frags{$ctg_name};
        my $offset = $fragment->{offset}    or die "No offset for '$ctg_name'";
        my $start  = $fragment->{start}     or die "No start for '$ctg_name'";
        my $end    = $fragment->{end}       or die "No end for '$ctg_name'";
        my $strand = $fragment->{strand}    or die "No strand for '$ctg_name'";

        my $cln  = $sequence{$ctg_name}     or die "No clone information for '$ctg_name'";
        my $acc  = $cln->{Accession}        or die "No Accession for '$ctg_name'";
        my $sv   = $cln->{Sequence_version} or die "No Sequence_version for '$ctg_name'";
        my $auth = $cln->{author};

        $start -= $chr_start - 1;
        $end   -= $chr_start - 1;

        # Make CloneInfo object
        my $info = Bio::Otter::CloneInfo->new;
        if ($auth) {
            my $author = $authors{$auth} or die "No Author object called '$auth'";
            $info->author($author);
        }
        if (my $kw_list = $cln->{Keyword}) {
            foreach my $word (@$kw_list) {
                my $kw = Bio::Otter::Keyword->new;
                $kw->name($word);
                $info->keyword($kw);
            }
        }
        if (my $rem_list = $cln->{Annotation_remark}) {
            foreach my $txt (@$rem_list) {
                my $remark = Bio::Otter::CloneRemark->new;
                $remark->remark("Annotation_remark- $txt");
                $info->remark($remark);
            }
        }
        if (my $de = $cln->{EMBL_dump_info}) {
            my $remark = Bio::Otter::CloneRemark->new;
            $remark->remark("EMBL_dump_info.DE_line- $de");
            $info->remark($remark);
        }
        

        # Make new clone and attatch CloneInfo
        my $clone = Bio::Otter::AnnotatedClone->new;
        $clone->id($acc);
        $clone->embl_version($sv);
        $clone->clone_info($info);
        
        # Make new contig and attach AnnotatedClone
        my $contig = Bio::EnsEMBL::RawContig->new;
        $contig->name($ctg_name);
        $contig->clone($clone);

        # Make new Tile and 
        my $tile = Bio::EnsEMBL::Tile->new;
        $tile->assembled_start($start + $chr_start - 1);
        $tile->assembled_end  ($end   + $chr_start - 1);
        $tile->component_start($offset);
        $tile->component_end  ($offset + $end - $start);
        $tile->component_ori  ($strand);
        $tile->component_Seq  ($contig);

        push(@$tile_path, $tile);
    }    
    
    #return(\@genes, \%frags, $assembly_type, $dna, $chr_name, $chr_start, $chr_end);
    return(\@genes, $tile_path, $assembly_type, $dna, $chr_name, $chr_start, $chr_end);
}

sub ace_to_XML {
    my( $fh ) = @_;
    
    #my( $genes, $frags, $type, $dna, $chr, $chrstart, $chrend ) = ace_to_otter($fh);
    my( $genes, $tile_path, $type, $dna, $chr, $chrstart, $chrend ) = ace_to_otter($fh);
    my $xml = "<otter>\n<sequence_set>\n"
        . path_to_XML($chr, $chrstart, $chrend, $type, $tile_path);
    foreach my $g (@$genes) {
        $xml .= $g->toXMLString;
    }
    $xml .= "\n</sequence_set>\n</otter>\n";
    return $xml;
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
        #print STDERR " Exon " . $exon->stable_id . "\n";
        #print STDERR " Phase " . $exon->phase . " EndPhase " . $exon->end_phase . "\n";
        #print STDERR " Strand " . $exon->strand . " Start " . $exon->start . " End ". $exon->end ."\n";

      if (defined($found)) {
        #print STDERR " Duplicate\n";
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
        #print STDERR "New = " . $exon->stable_id . "\n";

        ### This is nasty for the phases - sometimes exons come back with 
        ### the same stable id and different phases - we need to strip off
        ### the stable id if we think we have a new exon but we've
        ### already seen the stable_id

        if (defined($exon->stable_id) && defined($exonhash{$exon->stable_id})) {
           #print STDERR "Already seen stable id " . $exon->stable_id . " - removing stable_id\n";
           $exon->{_stable_id} = undef;
           #print STDERR "Exon id " .$exon->stable_id . "\n";
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

  my $xmlstr;

  $xmlstr .= "  <assembly_type>" . $type . "<\/assembly_type>\n";

  @$path = sort {$a->assembled_start <=> $b->assembled_start} @$path;

  foreach my $p (@$path) {
    $xmlstr .= "<sequence_fragment>\n";
    $xmlstr .= "  <accession>" . $p->component_Seq->id . "</accession>\n";
    $xmlstr .= "  <chromosome>" . $chr . "</chromosome>\n";

    if (my $clone = $p->component_Seq->clone) {
        $xmlstr .= clone_to_XML($clone);
    }

    $xmlstr .= "  <assembly_start>" . ($chrstart + $p->assembled_start() - 1) . "</assembly_start>\n";
    $xmlstr .= "  <assembly_end>" . ($chrstart + $p->assembled_end() - 1) . "</assembly_end>\n";
    $xmlstr .= "  <fragment_ori>" . $p->component_ori() . "</fragment_ori>\n";
    $xmlstr .= "  <fragment_offset>" . $p->component_start() . "</fragment_offset>\n";
    $xmlstr .= "</sequence_fragment>\n";
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

    if ($clone->isa("Bio::Otter::AnnotatedClone") && $clone->clone_info) {
        my $info = $clone->clone_info;
        if (my $author = $info->author) {
            $str .= $author->toXMLString;
        }

        my @remarks  = sort map $_->remark, $info->remark;
        foreach my $rem (@remarks) {
            $rem =~ s/\n/ /g;
            $str .= "  <remark>$rem<\/remark>\n";
        }

        my @keywords = sort map $_->name,   $info->keyword;
        foreach my $key (@keywords) {
            $str .= "  <keyword>$key<\/keyword>\n";
        }
     } else {
      print STDERR "\n\nCLONE '$clone' is not a Bio::Otter::AnnotatedClone\n";
     }
     return $str;
}

sub genes_to_XML_with_Slice {
  my ($slice, $genes, $writeseq,$path,$seqstr) = @_;

  my @genes = @$genes;

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequence_set>\n";

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
  #print STDERR "XML $xmlstr\n";  

  print STDERR "Writeseq $writeseq\n";
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

  $xmlstr .= "</sequence_set>\n";
  $xmlstr .= "</otter>\n";

  return $xmlstr;
}

sub slice_to_XML {
  my ($slice, $db, $writeseq) = @_;

  #print STDERR "Slice $slice : $db\n";

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequence_set>\n";

  my @path  = @{ $slice->get_tiling_path };
  #my @genes = @{ $db->get_GeneAdaptor->fetch_by_Slice($slice) };
  my @genes;

  if ($db->isa("Bio::Otter::DBSQL::DBAdaptor")) {
     @genes = @{ $db->get_GeneAdaptor->fetch_by_Slice($slice) };
   } else {
     # Is this ever used?  AnnotatedGenes from an non-otter database?
     my $tmpgenes = $db->get_GeneAdaptor->fetch_all_by_Slice($slice);
     foreach my $g (@$tmpgenes) {
         my $ann = bless $g,"Bio::Otter::AnnotatedGene";
         my $ginfo = new Bio::Otter::GeneInfo;
         $ann->gene_info($ginfo);
         push(@genes,$ann);
         my @tran;

          foreach my $t (@{$g->get_all_Transcripts}) {
            if (defined($t->translation)) {
              print STDERR "Translate " . $t->stable_id . " " . $t->translate->seq . "\n";
              my $tr = $t->translation;
              print STDERR "Tran " . $tr->start_Exon->stable_id . " " . $tr->end_Exon->stable_id. " " . $tr->start . " " . $tr->end . "\n";

              foreach my $ex (@{$t->get_all_Exons}) {
                 print STDERR $ex->stable_id . "\t" . $ex->gffstring . "\n";
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

    ### Checking author fetching
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

  $xmlstr .= "</sequence_set>\n";
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
        print STDERR "*****************************\n";
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
    } 

    # Now for the assembly stuff
    my $contig = $db->get_RawContigAdaptor->fetch_by_name($f);
    my $rawid   = $contig->dbID;
    my $length  = ($fend-$fstart+1);
    my $raw_end = $foff + ($fend-$fstart);

    #my $sqlstr = "insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values($chrid,$fstart,$fend,\'$f\',1,$length,1,$rawid,$foff,$raw_end,$fori,\'$assembly_type\')\n";

    my $sqlstr = q{
        INSERT INTO assembly(
            chromosome_id, chr_start, chr_end
          , superctg_name, superctg_start, superctg_end, superctg_ori
          , contig_id, contig_start, contig_end, contig_ori
          , type )
        VALUES( ?,?,?
            ,?,1,?,1
            ,?,?,?,?
            ,? ) 
        };
    #print "SQL $sqlstr\n";

    my $sth = $db->prepare($sqlstr);
    my $res = $sth->execute(
        $chrid, $fstart, $fend,
        $f, $length,
        $rawid, $foff, $raw_end, $fori,
        $assembly_type);

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

sub ace_unescape {
    my $str = shift;
    
    $str =~ s/\s+$//;       # Trim trailing whitespace.

    # Unescape quotes, back and forward slashes,
    # % signs, and semi-colons.
    $str =~ s/\\([\/"%;\\])/$1/g;
    
    return $str;
}

1;

