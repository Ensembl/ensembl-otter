package Bio::Otter::Converter;

use strict;
use warnings;
use Carp qw{ cluck confess };

use Bio::Otter::Author;
use Bio::Otter::AssemblyTag;
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
use Bio::EnsEMBL::SimpleFeature;
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
  my $accession;
  my $version;

  # These two hashes are to check that we don't
  # have the same gene name more than once.
  my %seen_gene_name;
  my %seen_transcript_name;

  my $feature_set = [];
  my $assembly_tag_set = [];
  my $at;

    ### <sequence_set> tag is ignored - parser will produce rubbish with multiple sequence_sets

  while (<$fh>) {
    chomp;
    if (/<locus>/) {
      $gene     = Bio::Otter::AnnotatedGene->new;
      $geneinfo = Bio::Otter::GeneInfo->new;
      $author   = Bio::Otter::Author->new;

      $gene->gene_info($geneinfo);
      $geneinfo->author($author);
      push (@genes, $gene);

      $currentobj = 'gene';
      $tran = undef;
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
        $geneinfo->known_flag($1);
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

      $tran     = Bio::Otter::AnnotatedTranscript->new;
      $traninfo = Bio::Otter::TranscriptInfo->new;
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

          if (!defined($start_exon)) {warn "no start exon"};
          if (!defined($end_exon)) {warn "no end exon"};


          print STDERR "ERROR: Failed mapping translation to transcript\n";
        } else {
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
      $traninfo->add_Evidence($evidence);
      $currentobj = 'evidence';
    } elsif (/<\/evidence>/) {
      $currentobj = 'tran';
    } elsif (/<name>(.*)<\/name>/) {

      if ($currentobj eq 'evidence') {
        $evidence->name($1);
      } elsif ($currentobj eq 'tran') {
        if ($seen_transcript_name{$1}) {
            confess "more than one transcript has the name '$1'";
        } else {
            $seen_transcript_name{$1} = 1;
        }
        $traninfo->name($1);
      } elsif ($currentobj eq 'gene') {
        if ($seen_gene_name{$1}) {
            confess "more than one gene has the name '$1'";
        } else {
            $seen_gene_name{$1} = 1;
        }
        $geneinfo->name(new Bio::Otter::GeneName(-name => $1));
      } else {
        die "ERROR: name tag only associated with evidence, transcript or gene - obj is $currentobj\n";
      }
    } elsif (/<\/evidence_set>/) {
      $currentobj = 'tran';
    }
    elsif (/<synonym>(.*)<\/synonym>/) {
      if ($currentobj eq 'gene') {
 	my $syn = new Bio::Otter::GeneSynonym(-name => $1);
        $geneinfo->synonym($syn);
      }
      else {
        die "ERROR: synonym tag only associated with gene objects. Object is [$currentobj]\n";
      }
    }
    elsif (/<description>(.*)<\/description>/) {

      if ($currentobj eq 'gene') {
        $gene->description($1);
      } else {
        die "ERROR: description tag only associated with gene objects. Object is [$currentobj]\n";
      }
    }
    elsif (/<truncated>(.*)<\/truncated>/) {

      if ($currentobj eq 'gene') {
        $geneinfo->truncated_flag($1);
      } else {
        die "ERROR: truncated tag only associated with gene objects. Object is [$currentobj]\n";
      }
    }
    elsif (/<type>(.*)<\/type>/) {

      if ($currentobj eq 'evidence') {
        $evidence->type($1);
      }
      elsif ($currentobj eq 'gene') {
        $gene->type($1);
      }
      else {
        die "ERROR: <type> tag only valid with evidence or gene - obj is $currentobj\n";
      }
    } elsif (/<sequence_fragment>/) {
      $currentobj = 'frag';
      $author = Bio::Otter::Author->new;

    } elsif (/<\/sequence_fragment>/) {
       if (defined($accession) && defined($version)) {

         my $cloneobj = new Bio::Otter::AnnotatedClone;

         $cloneobj->embl_id($accession);
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
       $accession = undef;
       $version = undef;

       @cloneremarks = ();
       @keywords     = ();

    } elsif (/<accession>(.*)<\/accession>/) {
      if ($currentobj eq 'frag') {
         $accession = $1;
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

    } elsif (/<id>(.*)<\/id>/) {
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

    }

    elsif (/<assembly_tag>/) {
      $at = Bio::Otter::AssemblyTag->new;
      while (<$fh>) {
	if (/<contig_strand>(.+)<\/contig_strand>/) {
	  $at->strand($1);
	}
	elsif (/<tag_type>(.+)<\/tag_type>/) {
	  $at->tag_type($1);
	}
	elsif (/<contig_start>(.+)<\/contig_start>/) {
	  $at->start($1);
	}
	elsif (/<contig_end>(.+)<\/contig_end>/) {
	  $at->end($1);
	}
	elsif (/<tag_info>(.+)<\/tag_info>/) {
	  $at->tag_info($1);
	}
	elsif (/<tag_id>(.+)<\/tag_id>/) {
	  $at->tag_id($1);
	}
	elsif (/<contig_id>(.+)<\/contig_id>/) {
	  $at->contig_id($1);
	}
	elsif (/<\/assembly_tag>/) {
	  push(@$assembly_tag_set, $at);
	  last;
	}
	else {
	  die "Unexpected line: $_";
	}
      }
    }

    elsif (/<.*?>.*<\/.*?>/) {
      print STDERR "ERROR: Unrecognised tag [$_]\n";
    }
    elsif (!/</ && !/>/) {
      if ($currentobj eq 'dna') {
        s/^\s*//;
        s/\s*$//;
        $seqstr .= $_;
        if (length($seqstr)%1_000_000 < 100) {
          #print STDERR "Found seq " . length($seqstr) . "\n";
        }
      }
    }

    elsif (/<feature_set>/) {
      XML_to_features($fh, $feature_set);
    }
    elsif (/<\/otter>/) {
      $foundend = 1;
    }
    #else {
    #    warn "UNKNOWN TAG: $_";
    #}
  }

  if (!$foundend) {
     print STDERR "Didn't find end tag <\/otter>\n";
  }

  ### End of XML parsing ###

  # Make the sequence fragments
  my @contigs;

  my $chrname  = undef;
  my $chrstart = undef;
  my $chrend   = undef;

  foreach my $f (keys %frag) {
    my $frag_data = $frag{$f};
    if ($chrname and $chrname ne $frag_data->{chr}) {
      print STDERR "fname = " . $f . "\n";
      print STDERR "frag id = " . $frag_data->{id} . "\n";
      die " Chromosome names are different - can't make slice [$chrname]["
        . $frag_data->{chr} . "]\n";
    } else {
        $chrname = $frag_data->{chr};
    }

    if (!defined($chrstart) or $frag_data->{start} < $chrstart) {
      $chrstart = $frag_data->{start};
    }

    if (!defined($chrend) or $frag_data->{end} > $chrend) {
      $chrend = $frag_data->{end};
    }

    my $tile = new Bio::EnsEMBL::Tile();

    my $offset = $frag_data->{offset};
    my $start  = $frag_data->{start};
    my $end    = $frag_data->{end};
    my $strand = $frag_data->{strand};

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
    $contig->clone($frag_data->{clone});

    $tile->component_Seq($contig);

   push(@tiles,$tile);
  }

  #$assembly_type = 'fake_gp_1' if (!defined($assembly_type));

  unless ($chrname and $chrstart and $chrend) {
      die "XML does not contain information needed to create slice:\n",
        "chr name='$chrname'  chr start='$chrstart'  chr end='$chrend'";
  }

  $slice = new Bio::EnsEMBL::Slice(-chr_name  => $chrname,
                                   -chr_start => $chrstart,
                                   -chr_end   => $chrend,
                                   -strand    => 1,
                                   -assembly_type => $assembly_type);


  #$slice->seq($seqstr);

  @tiles     = sort { $a->assembled_start <=> $b->assembled_start} @tiles;

  # print STDERR "chrname = " . $chrname . " chrstart = " . $chrstart . " chrend = "
  #  . $chrend . "\n";

  # If we have a database connection, check that our tile 
  # is consistent with the assembly table in the database
  if (defined($db)) {
    if ($assembly_type) {
      $db->assembly_type($assembly_type);
    }
    my $sa    = $db->get_SliceAdaptor;
    $slice = $sa->fetch_by_chr_start_end($chrname, $chrstart, $chrend)
        or confess "Can't get slice for chr '$chrname' $chrstart-$chrend on $assembly_type";

    my $path = $slice->get_tiling_path;

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

  # The xml coordinates are all in chromosomal coords - these
  # Need to be converted back to slice coords 
  if ($chrstart != 2000000000) {
    foreach my $gene (@genes) {
      foreach my $exon (@{ $gene->get_all_Exons }) {
        $exon->start($exon->start - $chrstart + 1);
        $exon->end(  $exon->end   - $chrstart + 1);
      }
    }
  }

  # Features need similarly to be fixed
  {
    my $offset = 1 - $chrstart;
    foreach my $feat (@$feature_set) {
      $feat->start($feat->start + $offset);
      $feat->end(  $feat->end   + $offset);
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
  return (\@genes, $slice, $seqstr, \@tiles, $feature_set, $assembly_tag_set);
}

sub XML_to_features {
    my( $fh, $feature_set ) = @_;

    my( %logic_ana );
    while (<$fh>) {
        if (/<feature>/) {
            my $sf = Bio::EnsEMBL::SimpleFeature->new;
            while (<$fh>) {
                if (/<start>(.+)<\/start>/) {
                    $sf->start($1);
                }
                elsif (/<end>(.+)<\/end>/) {
                    $sf->end($1);
                }
                elsif (/<strand>(.+)<\/strand>/) {
                    $sf->strand($1);
                }
                elsif (/<score>(.+)<\/score>/) {
                    $sf->score($1);
                }
                elsif (my ($type) = /<type>(.+)<\/type>/) {
                    my $ana = $logic_ana{$type} ||= Bio::EnsEMBL::Analysis->new(-LOGIC_NAME => $type);
                    $sf->analysis($ana);
                }
                elsif (/<label>(.+)<\/label>/) {
                    $sf->display_label($1);
                }
                elsif (/<\/feature>/) {
                    push(@$feature_set, $sf);
                    last;
                }
            }
        }
        elsif (/<\/feature_set>/) {
            return 1;
        }
    }

    confess "Failed to find closing </feature_set> tag";
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
    my ($slice, $genes, $path, $seq, $feature_set, $assembly_tag_set) = @_;

    my $slice_name = $slice->display_id;


    my $str =  qq{\n\nSequence : "$slice_name"\nAssembly\n};
    $str .= sprintf qq{Assembly_name "%s"\n}, $slice->assembly_type;

    unless (@$path) {
      $path = $slice->get_tiling_path;
    }

    my $chr      = $slice->chr_name;
    my $chrstart = $slice->chr_start;


    # Add SMap tags for assembly
    foreach my $tile (@$path) {
        ### I think assembled_start should not need chr start taking away
        ### - probably should have been done already
        my $start           = $tile->assembled_start - $chrstart + 1;
        my $end             = $tile->assembled_end   - $chrstart + 1;

        my $tile_length = $end - $start + 1;

        my $contig_start    = $tile->component_start;
        my $name            = $tile->component_Seq->name;

        if ($tile->component_ori == 1) {
            $str .= qq{AGP_Fragment "$name" $start $end Align $start $contig_start $tile_length\n};
        } else {
            # Clone in reverse orientaton in AGP is indicated
            # to acedb by first coordinate > second
            $str .= qq{AGP_Fragment "$name" $end $start Align $end $contig_start $tile_length\n};
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

    # Features (polyA signals and sites etc...)
    if (defined $feature_set->[0]) {
        foreach my $sf (@$feature_set) {
            my $start = $sf->start;
            my $end   = $sf->end;
            if ($sf->strand == -1) {
                ($start, $end) = ($end, $start);
            }
            my $type  = $sf->analysis->logic_name or die "no logic_name on analysis object";
            my $score = $sf->score;
            $score = 1 unless defined $score;
            if (my $label = $sf->display_label) {
                $str .= qq{Feature "$type" $start $end $score "$label"\n};
            } else {
                $str .= qq{Feature "$type" $start $end $score\n};
            }
        }
    }

    # assembly tag data
    if (defined $assembly_tag_set->[0]) {
      foreach my $at (@$assembly_tag_set) {

        # coords are same as XML from otter db (ie, all -1 <-> 1 and all start coord <= end coord)
	    my ($start, $end);
        ($at->strand == 1) ? ($start = $at->start, $end = $at->end) : ($start=$at->end, $end=$at->start);
	
	    my $tag_type = $at->tag_type;
	    my $tag_info = $at->tag_info;

	    $str .= qq{Assembly_tags "$tag_type" $start $end "$tag_info"\n};
      }
    }

    my $clone_context = '' ;
    my $original_start = $$path[0]->assembled_start ; 
    foreach my $tile (@$path) {

        my $clone        = $tile->component_Seq->clone;
        my $name         = $tile->component_Seq->name;
        my $accession    = $clone->embl_id       or die "No embl_id on clone attached to '$name' in tile";
        my $sv           = $clone->embl_version  or die "No embl_version on clone attached to '$name' in tile";;
        my $clone_info   = $clone->clone_info;
        my $orientation  = $tile->component_ori ;
        my $clone_length = $tile->component_end - $tile->component_start + 1 ;

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

	## add CloneContext object - so that annotators can  see features as clone coords
        my ( $contig_start , $contig_end, $gp_start, $target_start , $contig_length );

        $contig_start  = 1; 
        $contig_end    = $tile->component_end  ;

        $gp_start = $tile->component_start ;
        $target_start = $tile->assembled_start  - $original_start + 1;
        $contig_length = $tile->assembled_end - $tile->assembled_start  + 1;

        $clone_context .= qq{\nSequence "CloneCtxt-$name" \n} ;
        if ($orientation == 1 ){
            $clone_context .= qq{AGP_Fragment "$slice_name" $contig_start $contig_end Align $gp_start $target_start $contig_length\n} ;
        }else{
            $clone_context .= qq{AGP_Fragment "$slice_name" $contig_end $contig_start Align $contig_end $target_start $contig_length\n} ;
        }
        $clone_context .= qq{CloneContext\n} ;

        $str .= "\n$clone_context\n";
    }

    $str .= ace_transcripts_locus_people($genes, $slice);

    if ($seq) {
        # Finally the dna
        $str .= "\nDNA \"" . $slice->display_id . "\"\n";
        while ($seq =~ /(.{1,72})/g) {
            $str .= $1 . "\n";
        }
    }
     return $str;
}

sub ace_transcripts_locus_people{
    my ($genes, $slice) = @_;
    my (%authors, $str);
    # Add Sequence objects for Transcripts
    $str = ace_transcript_seq_objs_from_genes($genes, $slice, \%authors);
    $str .= "\n";
    # Locus objects for genes
    $str .= ace_locus_objs_from_genes($genes, \%authors);
    # Authors
    $str .= ace_people_from_authors(\%authors);
    return $str;
}

sub ace_people_from_authors{
    my ($authors) = @_;
    my $str = '';
    return $str unless ref($authors) eq 'HASH';
    foreach my $author (values %$authors) {
        my $name  = $author->name;
        my $email = $author->email;
        $str     .= qq{\nPerson : "$name"\nEmail "$email"\n};
    }
    return $str;
}

sub ace_transcript_seq_objs_from_genes{
    my ($genes, $slice, $authors) = @_;
    my $str = '';

    # Add Sequence objects for Transcripts
    foreach my $gene (@$genes) {
        my $gene_name;
        my $info = $gene->gene_info;
        if (my $gn = $info->name) {
            $gene_name = $gn->name;
        }
        $gene_name ||= $gene->stable_id;
        my $prefix = $gene->gene_type_prefix;

        foreach my $tran (@{ $gene->get_all_Transcripts }) {
            my $tran_name = $tran->transcript_info->name || $tran->stable_id;

            $str .= qq{\n-D Sequence : "$tran_name"\n\n};

            $str .= "Sequence : \"" . $tran_name . "\"\n";
            $str .= "Transcript_id \"" . $tran->stable_id . "\"\n";
            $str .= "Source \"" . $slice->display_id . "\"\n";
            $str .= "Locus \"" . $gene_name . "\"\n";
            if (my $author = $tran->transcript_info->author) {
                my $name  = $author->name;
                # author has a unique key in the database
                $authors->{$author->email} ||= $author;
                $str .= qq{Transcript_author "$name"\n};
            }

            # Transcript class determines acedb Method which
            # controls the transcript's appearance in fMap.
            my $method = $tran->transcript_info->class->name;
            $str .= sprintf qq{Method "%s"\n},
                ($prefix ? "$prefix:" : '')
                . $method
                . ($info->truncated_flag ? '_trunc' : '');

            # Extra tags needed by ace
            if ($method =~ /supported_mRNA/) {
                $str .= "Processed_mRNA\n";     ### check this
            } elsif ($method =~ /pseudo/i) {
                $str .= "Pseudogene\nCDS\n";
            }

            # Annotation remarks are stored in the same field in otter,
            # but appear under a different tag in acedb.
            my @remarks = $tran->transcript_info->remark;
            foreach my $remark (sort map $_->remark, @remarks) {
                if ($remark =~ s/^Annotation_remark- //) {
                    $str .= "Annotation_remark \"" . ace_escape($remark) . "\"\n";
                } else {
                    $str .= "Remark \"" . ace_escape($remark) . "\"\n";
                }
            }

            # Supporting evidence
            my @ev = sort {$a->name cmp $b->name} @{$tran->transcript_info->get_all_Evidence};
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
    return $str;
}

sub ace_locus_objs_from_genes {
    my ($genes, $authors) = @_;
    my $str = '';

    # Locus objects for genes
    foreach my $gene (@$genes) {
        my $info = $gene->gene_info;
        my $gene_name;
        if ($info->name && $info->name->name) {
            $gene_name = $info->name->name;
        } else {
            $gene_name = $gene->stable_id;
        }

        $str .= qq{\n-D Locus : "$gene_name"\n\n};

        $str .= "Locus : \"" . $gene_name . "\"\n";
        foreach my $synonym ($info->synonym) {
            $str .= "Alias \"" . $synonym->name . "\"\n";
        }

        $str .= "Known\n"     if $info->known_flag;
        $str .= "Truncated\n" if $info->truncated_flag;

        if (my $author = $info->author) {
            my $name  = $author->name;
            # email has a unique key in the database
            $authors->{$author->email} ||= $author;
            $str .= qq{Locus_author "$name"\n};
        }

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

        if (my $desc = $gene->description) {
            $str .= qq{Full_name "$desc"\n};
        }
        foreach my $rem ( $info->remark ) {
	        my $txt = $rem->remark;

	        if ($txt =~ s/^Annotation_remark- //) {
	            $str .= qq{Annotation_remark "$txt"\n};
	        } else {
	            $str .= qq{Remark "$txt"\n};
	        }
	    }
        if (my $prefix = $gene->gene_type_prefix) {
            $str .= qq{Type_prefix "$prefix"\n};
        }

        $str .= "\n";
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
    my ($fh) = @_;

    my (
        %sequence,     # Accumulates Sequence information keyed by sequence name
        %genes,        # Accumulates Locus information keyed by locus name
        %genenames,    # Links Sequence names to Locus names
        %authors,      # Bio::Otter::Author objects keyed by author name
        %frags,        # hashes used to capture genomic fragment tiling data
        %logic_ana,    # Analysis objects for SimpleFeatures keyed by logic name
        $slice_name,   # Name of the parent Genomic sequence
        $assembly_type,
        $chr_name,
        $chr_start,
        $chr_end,
        $dna,
    );

 # Main parsing loop - might be more effecient to split on objects (ie: $/ = "")
    while (<$fh>) {

        # Parse Sequence object, which could be
        # Genomic (slice) or SubSequence (transcript)
        if (/^Sequence $OBJ_NAME/x) {
            my $currname = $1;
            my $curr_seq = $sequence{$currname} ||= {};

            #print STDERR "Found sequence [$currname]\n";

            ### Could slightly optimize this loop by moving the more numerous lines nearer to the top
            while (($_ = <$fh>) !~ /^\n$/) {

                if (/^Subsequence $STRING $INT $INT/x) {
                    my $name  = ace_unescape($1);
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
                    $assembly_type = ace_unescape($1);

                    #print STDERR $1, "\n";
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
                    my $name  = ace_unescape($1);
                    my $start = $2;
                    my $end   = $3;

                    # Don't need $4
                    my $offset = $5;

                    ### Not yet tested for reverse strand!
                    my $strand = 1;
                    if ($start > $end) {
                        $strand = -1;
                        ($start, $end) = ($end, $start);
                    }

                    $frags{$name} = {
                        start  => $start,
                        end    => $end,
                        offset => $offset,
                        strand => $strand,
                    };
                }
                elsif (/^Assembly\W$/) {
                    if ($currname =~ /(\S+)\.(\d+)-(\d+)/) {
                        $chr_name   = $1;
                        $chr_start  = $2;
                        $chr_end    = $3;
                        $slice_name = undef;
                    }
                    else {
                        print STDERR
"Warning: Assembly sequence is not in the 6.1-10000 format [$currname].  Can't convert to chr, start,end\n";
                    }

                    #print STDERR "Found contig\n";

                    if ($slice_name) {
                        die "Only one Assembly sequence allowed\n";
                    }
                    else {
                        $slice_name = $currname;
                    }
                }

                elsif (/^Assembly_tags $STRING $INT $INT $STRING/x) {
                    my $type = ace_unescape($1);
                    my ($start, $end, $strand) = decide_strand($2, $3);
                    my $info = ace_unescape($4);

                    my $at = Bio::Otter::AssemblyTag->new;
                    $at->tag_type($type);
                    $at->tag_info($info);
                    $at->start($start);
                    $at->end($end);
                    $at->strand($strand);

                    my $assembly_tag_set = $curr_seq->{'assembly_tag_set'} ||=
                      [];
                    push @$assembly_tag_set, $at;
                }

                elsif (/^(Keyword|Remark|Annotation_remark) $STRING/x) {
                    my $anno_txts = $curr_seq->{$1} ||= [];
                    push @$anno_txts, ace_unescape($2);
                }
                elsif (/^EMBL_dump_info\s+DE_line $STRING/x) {
                    $curr_seq->{EMBL_dump_info} = ace_unescape($1);
                }
                elsif (/^Feature $STRING $INT $INT $FLOAT (?:$STRING)?/x) {
                    my $type = ace_unescape($1);
                    my ($start, $end, $strand) = decide_strand($2, $3);
                    my $score = $4;
                    my $label = ace_unescape($5);

                    my $ana = $logic_ana{$type} ||=
                      Bio::EnsEMBL::Analysis->new(-LOGIC_NAME => $type);
                    my $sf = Bio::EnsEMBL::SimpleFeature->new(
                        -ANALYSIS => $ana,
                        -START    => $start,
                        -END      => $end,
                        -STRAND   => $strand,
                        -SCORE    => $score,
                    );
                    $sf->display_label($label) if $label;

                    my $feature_set = $curr_seq->{'feature_set'} ||= [];
                    push @$feature_set, $sf;
                }

                elsif (/^Source $STRING/x) {

                    # We have a gene and not a contig.
                    $curr_seq->{Source} = ace_unescape($1);

                    my $tran = Bio::Otter::AnnotatedTranscript->new;
                    $curr_seq->{transcript} = $tran;

                    #print STDERR "new tran  $currname [$tran][$val]\n";
                }
                elsif (/^Source_Exons $INT $INT (?:$STRING)?/x) {
                    my $oldstart = $1;
                    my $oldend   = $2;
                    my $stableid =
                      ace_unescape($3);    # Will not always have a stable_id

                    my $tstart  = $curr_seq->{start};
                    my $tend    = $curr_seq->{end};
                    my $tstrand = $curr_seq->{strand};

                    my $start;
                    my $end;

                    if ($tstrand == 1) {
                        $start = $oldstart + $tstart - 1;
                        $end   = $oldend + $tstart - 1;
                    }
                    else {
                        $end   = $tend - $oldstart + 1;
                        $start = $tend - $oldend + 1;
                    }

                    #print STDERR "Adding exon at $start $end to $currname\n";
                    my $exon = new Bio::EnsEMBL::Exon(
                        -start  => $start,
                        -end    => $end,
                        -strand => $tstrand
                    );
                    $exon->stable_id($stableid);

                    ### This assumes the "Source" tag will always be encountered before Exon tags - bad
                    $curr_seq->{transcript}->add_Exon($exon);
                }
                elsif (
/^(cDNA_match|Protein_match|Genomic_match|EST_match) $STRING/x
                  )
                {
                    my $matches = $curr_seq->{$1} ||= [];
                    push @$matches, ace_unescape($2);
                }
                elsif (/^Locus $STRING/x) {
                    $genenames{$currname} = ace_unescape($1);
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
                    $curr_seq->{Start_not_found} = $phase;
                }
                elsif (/^Start_not_found/) {
                    $curr_seq->{Start_not_found} = -1;
                }
                elsif (/^Method $STRING/x) {
                    my $meth = ace_unescape($1);
                    # Strip any prefix from the method
                    $meth =~ s/^[A-Z_]+://;
                    $curr_seq->{Method} = $meth;
                }
                elsif (/^(Processed_mRNA|Pseudogene)/) {
                    $curr_seq->{$1} = 1;
                }
                elsif (
/^(Transcript_id|Translation_id|Transcript_author|Accession) $STRING/x
                  )
                {
                    $curr_seq->{$1} = ace_unescape($2);
                }
                elsif (/^Sequence_version $INT/x) {
                    $curr_seq->{Sequence_version} = $1;
                }
            }
        }

        # Parse Locus objects
        elsif (/^Locus $OBJ_NAME/x) {
            my $name     = $1;
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
                    push @$tran_list, ace_unescape($1);
                }
                elsif (/^(Locus_(?:id|author)) $STRING/x) {
                    $cur_gene->{$1} = ace_unescape($2);
                }
                elsif (/^Truncated/) {
                    $cur_gene->{Truncated} = 1;
                }
                elsif (/^(Remark|Annotation_remark) $STRING/x) {
                    my $remark_list = $cur_gene->{'remarks'} ||= [];
                    my $remark =
                      $1 eq 'Annotation_remark' ? "Annotation_remark- $2" : $2;
                    push(@$remark_list, ace_unescape($remark));
                }
                elsif (/^Alias $STRING/x) {
                    my $alias_list = $cur_gene->{'aliases'} ||= [];
                    push(@$alias_list, ace_unescape($1));
                }
                elsif (/^Full_name $STRING/x) {
                    $cur_gene->{'description'} = ace_unescape($1);
                }
                elsif (/^(Type_prefix) $STRING/x) {
                    $cur_gene->{$1} = ace_unescape($2);
                }
            }
        }

        # Parse Person objects
        elsif (/^Person $OBJ_NAME/x) {

            #warn "Found Person '$1'";
            my $author_name = $1;
            my ($author_email);
            while (($_ = <$fh>) !~ /^\n$/) {

                #print STDERR "Person: $_";
                if (/^Email $STRING/x) {
                    $author_email = ace_unescape($1);
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

    print STDERR "Slice is '$slice_name'\n";
    die "Failed to find name of slice" unless $slice_name;

    my %anntran;

    # Make transcripts and translations
  SEQ: while (my ($seq, $seq_data) = each %sequence) {
        my $transcript = $seq_data->{transcript} or next SEQ;
        next SEQ unless @{ $transcript->get_all_Exons };

        #print STDERR "Seq = $seq\n";

        my $source = $seq_data->{Source};

        #print STDERR "Key $seq    $source    $slice_name\n";
        next SEQ unless $source and $source eq $slice_name;

        if (my $tsid = $seq_data->{Transcript_id}) {
            $transcript->stable_id($tsid);
        }

        my $traninfo = new Bio::Otter::TranscriptInfo;
        $traninfo->name($seq);
        if (my $au_name = $seq_data->{Transcript_author}) {
            my $author = $authors{$au_name}
              or die "No author object '$au_name'";
            $traninfo->author($author);
        }

        # Remarks
        if (my $rem_list = $seq_data->{Annotation_remark}) {
            foreach my $txt (@$rem_list) {
                my $remark = Bio::Otter::TranscriptRemark->new;

             # Method should be "name" not "remark" for symetry with CloneRemark
                $remark->remark("Annotation_remark- $txt");
                $traninfo->remark($remark);
            }
        }
        if (my $remark_list = $seq_data->{Remark}) {
            foreach my $rem (@$remark_list) {
                my $remark = Bio::Otter::TranscriptRemark->new(-remark => $rem);
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
                        -type => $type,
                        -name => $name,
                    );
                    push(@evidence, $obj);
                }
            }
        }
        $traninfo->add_Evidence(@evidence);

        # Type of transcript (Method tag)
        my $class =
          Bio::Otter::TranscriptClass->new(-name => $seq_data->{Method});
        $traninfo->class($class);

        #print STDERR "Defined $seq " . $seq_data->{transcript} . "\n";
        if (my $anntran = $seq_data->{transcript}) {

            $anntran->transcript_info($traninfo);

            $anntran{$seq} = $anntran;

            # Sort the exons here just in case
            #print STDERR "Anntran $seq [$anntran]\n";
            die "No exons in transcript '$seq'"
              unless @{ $anntran->get_all_Exons };
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
                }
                else {
                    $start_phase = 0;
                }

                my $phase     = -1;
                my $in_cds    = 0;
                my $found_cds = 0;
                my $mrna_pos  = 0;
                my $exon_list = $anntran->get_all_Exons;
                for (my $i = 0 ; $i < @$exon_list ; $i++) {
                    my $exon            = $exon_list->[$i];
                    my $strand          = $exon->strand;
                    my $exon_start      = $mrna_pos + 1;
                    my $exon_end        = $mrna_pos + $exon->length;
                    my $exon_cds_length = 0;
                    if ($in_cds) {
                        $exon_cds_length = $exon->length;
                        $exon->phase($phase);
                    }
                    elsif (!$found_cds and $cds_start <= $exon_end) {
                        $in_cds    = 1;
                        $found_cds = 1;
                        $phase     = $start_phase;

                        if ($cds_start > $exon_start) {

                            # beginning of exon is non-coding
                            $exon->phase(-1);
                        }
                        else {
                            $exon->phase($phase);
                        }
                        $exon_cds_length = $exon_end - $cds_start + 1;
                        $translation->start_Exon($exon);
                        my $t_start = $cds_start - $exon_start + 1;
                        die "Error in '$seq' : translation start is '$t_start'"
                          if $t_start < 1;
                        $translation->start($t_start);
                    }
                    else {
                        $exon->phase($phase);
                    }

                    my $end_phase = -1;
                    if ($in_cds) {
                        $end_phase = ($exon_cds_length + $phase) % 3;
                    }

                    if ($in_cds and $cds_end <= $exon_end) {

                        # Last translating exon
                        $in_cds = 0;
                        $translation->end_Exon($exon);
                        my $t_end = $cds_end - $exon_start + 1;
                        die "Error in '$seq' : translation end is '$t_end'"
                          if $t_end < 1;
                        $translation->end($t_end);
                        if ($cds_end < $exon_end) {
                            $exon->end_phase(-1);
                        }
                        else {
                            $exon->end_phase($end_phase);
                        }
                        $phase = -1;
                    }
                    else {
                        $exon->end_phase($end_phase);
                        $phase = $end_phase;
                    }

                    $mrna_pos = $exon_end;
                }
                $anntran->throw("Failed to find CDS in '$seq'")
                  unless $found_cds;

                if ($seq_data->{End_not_found}) {
                    my $last_exon_end_phase =
                      $exon_list->[$#$exon_list]->end_phase;
                    $traninfo->mRNA_end_not_found(1);
                    $traninfo->cds_end_not_found(1)
                      if $last_exon_end_phase != -1;
                }
            }
            else {

                # No translation, so all exons get phase -1
                foreach my $exon (@{ $anntran->get_all_Exons }) {
                    $exon->phase(-1);
                    $exon->end_phase(-1);
                }
                $traninfo->mRNA_start_not_found(1)
                  if defined $seq_data->{Start_not_found};
                $traninfo->mRNA_end_not_found(1)
                  if defined $seq_data->{End_not_found};
            }
        }
    }

    # Fix exon coordinates
    {
        my $offset = $chr_start - 1;
        foreach my $transcript (values %anntran) {
            foreach my $exon (@{ $transcript->get_all_Exons }) {

                #warn "got '$exon'\n";
                $exon->start($exon->start + $offset);
                $exon->end($exon->end + $offset);
            }
        }
    }

    # Make gene objects
    my @genes;
    while (my ($gname, $gene_data) = each %genes) {

        #print STDERR "Gene name = $gname\n";
        my $gene  = Bio::Otter::AnnotatedGene->new;
        my $ginfo = Bio::Otter::GeneInfo->new;
        $gene->gene_info($ginfo);

        if (my $gsid = $gene_data->{Locus_id}) {
            $gene->stable_id($gsid);
        }
        if (my $au_name = $gene_data->{Locus_author}) {
            my $author = $authors{$au_name}
              || die "No author object '$au_name'";
            $ginfo->author($author);
        }

        # Gene description (from the Full_name tag)
        if (my $desc = $gene_data->{'description'}) {
            $gene->description($desc);
        }

        # Names and aliases (synonyms)
        $ginfo->name(Bio::Otter::GeneName->new(-name => $gname,));
        if (my $list = $gene_data->{'aliases'}) {
            foreach my $text (@$list) {
                my $synonym = Bio::Otter::GeneSynonym->new;
                $synonym->name($text);
                $ginfo->synonym($synonym);
            }
        }

        # Gene remarks
        if (my $list = $gene_data->{'remarks'}) {
            foreach my $text (@$list) {
                my $remark = Bio::Otter::GeneRemark->new;
                $remark->remark($text);
                $ginfo->remark($remark);
            }
        }
        $ginfo->truncated_flag(1) if $gene_data->{'Truncated'};

        #print STDERR "Made gene $gname\n";

        push(@genes, $gene);

        # We need to pair up the CDS transcript objects with the
        # mRNA objects and set the translations

        my @newtran;

      TRAN: foreach my $tranname (@{ $gene_data->{transcripts} }) {
            my $tran      = $anntran{$tranname};
            my $tran_data = $sequence{$tranname};

            #print STDERR "Converter: transcript name $tranname \n";
            unless ($tran) {
                warn
"Transcript '$tranname' in Locus '$gname' not found in ace data\n";
                next TRAN;
            }

            $gene->add_Transcript($tran);
        }

        prune_Exons($gene);

        my $ace_type = $gene_data->{GeneType};
        if ($ace_type and $ace_type =~ /known/i) {
            $ginfo->known_flag(1);
        }
        my $type =
          gene_type_from_transcript_set($gene->get_all_Transcripts,
            $ginfo->known_flag);
        if (my $prefix = $gene_data->{Type_prefix}) {
            $type = "$prefix:$type";
        }
        $gene->type($type);
    }

    # Turn %frags into a Tiling Path
    my $tile_path = [];
    foreach my $ctg_name (keys %frags) {
        my $fragment = $frags{$ctg_name};
        my $offset   = $fragment->{offset} or die "No offset for '$ctg_name'";
        my $start    = $fragment->{start} or die "No start for '$ctg_name'";
        my $end      = $fragment->{end} or die "No end for '$ctg_name'";
        my $strand   = $fragment->{strand} or die "No strand for '$ctg_name'";

        my $cln = $sequence{$ctg_name}
          or die "No clone information for '$ctg_name'";
        my $acc = $cln->{Accession} or die "No Accession for '$ctg_name'";
        my $sv = $cln->{Sequence_version}
          or die "No Sequence_version for '$ctg_name'";
        my $auth = $cln->{author};

        $start -= $chr_start - 1;
        $end   -= $chr_start - 1;

        # Make CloneInfo object
        my $info = Bio::Otter::CloneInfo->new;
        if ($auth) {
            my $author = $authors{$auth}
              or die "No Author object called '$auth'";
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
        $clone->embl_id($acc);
        $clone->embl_version($sv);
        $clone->clone_info($info);

        # Make new contig and attach AnnotatedClone
        my $contig = Bio::EnsEMBL::RawContig->new;
        $contig->name($ctg_name);
        $contig->clone($clone);

        # Make new Tile
        my $tile = Bio::EnsEMBL::Tile->new;
        $tile->assembled_start($start + $chr_start - 1);
        $tile->assembled_end($end + $chr_start - 1);
        $tile->component_start($offset);
        $tile->component_end($offset + $end - $start);
        $tile->component_ori($strand);
        $tile->component_Seq($contig);

        push(@$tile_path, $tile);
    }

    my $feature_set      = $sequence{$slice_name}{'feature_set'};
    my $assembly_tag_set = $sequence{$slice_name}{'assembly_tag_set'};

    return (
        \@genes,  $tile_path,   $assembly_type,
        $dna,     $chr_name,    $chr_start,
        $chr_end, $feature_set, $assembly_tag_set
    );

#   return(\@genes, $tile_path, $assembly_type, $dna, $chr_name, $chr_start, $chr_end, $feature_set);
}


sub decide_strand {
    my( $start, $end ) = @_;
    
    my $strand = 0;	# Will stay 0 if start == end
    if ($start < $end) {
        $strand = 1;
    } elsif ($start > $end) {
        $strand = -1;
        ($start, $end) = ($end, $start);
    }
    return($start, $end, $strand);
}

sub ace_to_XML {
    my( $fh ) = @_;

    #my( $genes, $frags, $type, $dna, $chr, $chrstart, $chrend ) = ace_to_otter($fh);
    my( $genes, $tile_path, $type, $dna, $chr, $chrstart, $chrend, $feature_set, $assembly_tag_set) = ace_to_otter($fh);

    my $xml = "<otter>\n<sequence_set>\n"
        . path_to_XML($chr, $chrstart, $chrend, $type, $tile_path)
        . (defined $feature_set->[0] ? features_to_XML($chrstart, $feature_set) : '')
        . ($assembly_tag_set ? assembly_tags_to_XML($assembly_tag_set) : '');

    foreach my $g (@$genes) {
        $xml .= $g->toXMLString;
    }

    $xml .= "\n</sequence_set>\n</otter>\n";

    return $xml;
}

sub prune_Exons {
    my ($gene) = @_;

    # keep track of all unique exons found so far to avoid making duplicates
    # need to be very careful about translation->start_exon and translation->end_Exon

    #cluck "Pruning exons";

    my( %stable_key, %unique_exons );

    foreach my $tran (@{ $gene->get_all_Transcripts }) {
        my( @transcript_exons );
        foreach my $exon (@{$tran->get_all_Exons}) {
            my $key = exon_hash_key($exon);
            if (my $found = $unique_exons{$key}) {
                # Use the found exon in the translation
                if ($tran->translation) {
                    if ($exon == $tran->translation->start_Exon) {
                        $tran->translation->start_Exon($found);
                    }
                    if ($exon == $tran->translation->end_Exon) {
                        $tran->translation->end_Exon($found);
                    }
                }
                # re-use existing exon in this transcript
                $exon = $found;
            } else {
                $unique_exons{$key} = $exon;
            }
            push (@transcript_exons, $exon);

            # Make sure we don't have the same stable IDs
            # for different exons (different keys).
            if (my $stable = $exon->stable_id) {
                if (my $seen_key = $stable_key{$stable}) {
                    if ($seen_key ne $key) {
                        $exon->{_stable_id} = undef;
                        printf STDERR  "Already seen exon_id '$stable' on different exon\n";
                    }
                } else {
                    $stable_key{$stable} = $key;
                }
            }
        }
        $tran->flush_Exons;
        foreach my $exon (@transcript_exons) {
            $tran->add_Exon($exon);
        }
    }
}

sub exon_hash_key {
    my( $exon ) = @_;
    
    # This assumes that all the exons we
    # compare will be on the same contig
    return join(" ",
        $exon->start,
        $exon->end,
        $exon->strand,
        $exon->phase,
        $exon->end_phase);
}

sub path_to_XML {
  my ($chr,$chrstart,$chrend,$type,$path) = @_;
  my $xmlstr;

  $xmlstr .= "  <assembly_type>" . $type . "<\/assembly_type>\n";

  @$path = sort {$a->assembled_start <=> $b->assembled_start} @$path;

  foreach my $p (@$path) {
    $xmlstr .= "<sequence_fragment>\n";
    $xmlstr .= "  <id>" . $p->component_Seq->id . "</id>\n";
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

    $str .= "  <accession>" . $clone->embl_id . "<\/accession>\n";
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

sub features_to_XML {
    my( $chrstart, $features ) = @_;

    confess "No chrstart" unless $chrstart =~ /\d+/;
    confess "No features" unless $features;

    my $offset = $chrstart - 1;

    my $xml = "<feature_set>\n";

      foreach my $sf (@$features) {
        my $type = $sf->analysis->logic_name;
        next if $type =~ /cpg/i;    ### Hack to ignore CpG analysis in xenopus cDNA database
        $xml .= "  <feature>\n"
            . sprintf("    <type>%s</type>\n",      $type                       )
            . sprintf("    <start>%s</start>\n",    $sf->start + $offset        )
            . sprintf("    <end>%s</end>\n",        $sf->end   + $offset        )
            . sprintf("    <strand>%s</strand>\n",  $sf->strand                 )
            . sprintf("    <score>%s</score>\n",    $sf->score                  )
            . sprintf("    <label>%s</label>\n",    $sf->display_label          )
            . "  </feature>\n";
      }

      $xml .= "</feature_set>\n";
      return $xml;
}

sub slice_to_XML {
  my ($slice, $db, $writeseq) = @_;

  print STDERR "Slice $slice\n";

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequence_set>\n";

  my $path  = $slice->get_tiling_path;
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

  $xmlstr .= Bio::Otter::Converter::path_to_XML($chr, $chrstart, $chrend, $db->assembly_type, $path);

    # Simple features for polyA signals and sites etc...
    if (my $feats = $slice->get_all_SimpleFeatures) {
      if ( defined $feats->[0] ){
        $xmlstr .= features_to_XML($chrstart, $feats);
      }
    }

    # get all assembly tag data
    $xmlstr .= assembly_tags_to_XML($slice, $db);

    if (defined($writeseq)) {
        $xmlstr .= "<dna>\n";
        my $seqstr = $slice->seq;
        $seqstr =~ s/(.{72})/  $1\n/g;
        $xmlstr .= $seqstr . "\n";
        $xmlstr .= "</dna>\n";
    }

    @genes = sort by_stable_id_or_name @genes;
    foreach my $g (@genes) {
        #print STDERR "Gene type " . $g->type . "\n";
        if ($g->type ne 'obsolete') {
            $xmlstr .= $g->toXMLString . "\n";
        }
    }

    $xmlstr .= "</sequence_set>\n";
    $xmlstr .= "</otter>\n";

    return $xmlstr;
}

sub assembly_tags_to_XML {
  my ($slice, $db) = @_;

  my ($str, $atag_Ad, $tag_data);

  if ( ref($slice) eq "Bio::EnsEMBL::Slice" ){
    $atag_Ad  = $db->get_AssemblyTagAdaptor;

    # $atags_Ad inherits from Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor,
    # which inherits from Bio::EnsEMBL::DBSQL:BaseAdaptor
    # This also allows fetching AssemblyTag features by passing a slice obj to fetch_all_by_Slice()

    $tag_data = $atag_Ad->fetch_all_by_Slice($slice);
  }

  # $slice here is actually array of AssemblyTag objs
  else {
    $tag_data = $slice;
  }

  foreach my $h ( @$tag_data ){
    ### FIXME! These coordinates should be in chromosomal space!
    ### See features_to_XML()
    $str .= "<assembly_tag>\n"
 	 . "  <contig_strand>" . $h->strand     . "</contig_strand>\n"	
         . "  <tag_type>"      . $h->tag_type   . "</tag_type>\n"
	 . "  <contig_start>"  . $h->start      . "</contig_start>\n"
	 . "  <contig_end>"    . $h->end        . "</contig_end>\n"
	 . "  <tag_info>"      . $h->tag_info   . "</tag_info>\n"
         . "</assembly_tag>\n";
  }

  return $str;
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

### Not used
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
      #$clone->id($f);
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
    
    $str =~ s/^\s+//;       # Trim leading whitespace.
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
    
    $str =~ s/^\s+//;       # Trim leading whitespace.
    $str =~ s/\s+$//;       # Trim trailing whitespace.

    # Unescape quotes, back and forward slashes,
    # % signs, and semi-colons.
    $str =~ s/\\([\/"%;\\])/$1/g;
    
    return $str;
}


=head1 gene_type_from_transcript_set

    my $type = gene_type_from_transcript_set(\@transcripts, $known_flag);

See the section on transcript classes in the
otter XML documentation.

Sets the C<type> on the gene using a decision
tree based on a list of known transcript classes.

If there is an transcript class which is unknown
by the method, but this is the only class in the
gene, then this class name is used as the gene
C<type>.  If, however, the gene contains a mix of
unknown transcript classes the method throws an
exception.

Exceptions are also thrown when the gene contains
more than one class of pseudogene transcript, and
when there are no transcript in the gene.

=cut

sub gene_type_from_transcript_set {
    my( $transcripts, $known_flag ) = @_;
    
    my $pseudo_count = 0;
    my $has_artifact = 0;
    my $class_set = {};
    foreach my $transcript (@$transcripts) {
        my $class = $transcript->transcript_info->class->name;
        $class =~ s/^([^:]+)://;    # Strip leading GD. etc ...
        $class =~ s/_trunc$//;
        if ($class eq 'Artifact') {
            $has_artifact = 1;
            next;   # Artifact type is silent and doesn't influence
                    # the gene type unless it is the only transcript
                    # class in the gene.
        }
        $class_set->{$class}++;
        if ($class =~ /pseudo/i) {
            $pseudo_count++;
        }
    }
    
    my( $type );
    my @class_list = keys %$class_set;
    # If there are any Pseudogene transcripts, the gene is either
    # a Pseudogene, or it is a Polymorphic locus if there are other
    # classes of transcripts present.
    if ($pseudo_count) {
        if ($pseudo_count == @$transcripts) {
            if (@class_list > 1) {
                confess("Have mix of pseudogene classes in gene:\n"
                    . join('', map "  $_\n", @class_list));
            } else {
                ($type) = @class_list;
            }
        } else {
            ### May not have this any more now we have 1 gene object per haplotype.
            $type = 'Polymorphic';
        }
    }
    # All genes containing protein coding transcripts are either Known or Novel_CDS
    elsif ($class_set->{'Coding'}) {
        # Check for the known_flag flag on the GeneInfo object
        if ($known_flag) {
            $type = 'Known';
        }
        else {
            $type = 'Novel_CDS';
        }
    }
    # Gene type is Novel_Transcript if any of these are present
    elsif ($class_set->{'Transcript'}
        or $class_set->{'Non_coding'}
        or $class_set->{'Ambiguous_ORF'}
        or $class_set->{'Immature'}
        or $class_set->{'Antisense'}
        )
    {
        $type = 'Novel_Transcript';
    }
    # All remaining gene types are only expected to have one class of transcript
    elsif (@class_list > 1) {
        confess("Have mix of transcript classes in gene where not expected:\n"
            . join('', map "  $_\n", @class_list));
    }
    else {
        # Gene type is the same as the transcript type
        unless ($type = $class_list[0]) {
            if ($has_artifact) {
                # Artifact it the only transcript type in the gene
                $type = 'Artifact';
            } else {
                confess "No transcript classes";
            }
        }
    }
    return $type;
}

1;

