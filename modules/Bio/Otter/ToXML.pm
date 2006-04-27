package ToXML; # a module, but not really a class

use strict;

# ----------------[simplify some formatting]----------------------

sub emit_opening_tag {
    my ($tag, $offset) = (@_, 0);

    return ( (' ' x $offset) . '<' . $tag . ">\n") ;
}

sub emit_closing_tag {
    my ($tag, $offset) = (@_, 0);

    return ( (' ' x $offset) . '</' . $tag . ">\n") ;
}

sub emit_tagpair {
    my ($tag, $value, $offset) = @_;

    if(!defined($value)) { return ''; }
    # $value    = '' unless defined($value); # not to transform a zero into empty string!

    $offset ||= 0;

    return ( (' ' x $offset) . '<' . $tag . '>' . $value . '</' . $tag . ">\n") ;
}


# ----------------[original Bio::EnsEMBL::... classes]--------------

sub Bio::EnsEMBL::DBEntry::toXMLstring {
    my $dbentry = shift @_;

    my $str = '';

    $str .= emit_opening_tag('xref',2);
    $str .= emit_tagpair('primary_id', $dbentry->primary_id(), 4);
    $str .= emit_tagpair('display_id', $dbentry->display_id(), 4);
    $str .= emit_tagpair('version', $dbentry->version(), 4);
    $str .= emit_tagpair('release', $dbentry->release(), 4);
    $str .= emit_tagpair('dbname', $dbentry->dbname(), 4);
    $str .= emit_tagpair('description', $dbentry->description(), 4);
    $str .= emit_closing_tag('xref',2);

    return $str;
}

sub Bio::EnsEMBL::Gene::toXMLstring {
    my $gene = shift @_;

    my $coord_offset = 0;
    my $slice_length = 0;

        # determine if gene is on a slice
    my $exons = $gene->get_all_Exons;
    if (scalar(@$exons) && (my $firstexon=$exons->[0])) {
        if($firstexon->can('slice')) { # new API
            $coord_offset = $firstexon->slice()->start()-1;
            $slice_length = $firstexon->slice()->length();
        } else {    # old API
            my $contig = $firstexon->contig();
            if (defined($contig) && $contig->isa("Bio::EnsEMBL::Slice")) {
                $coord_offset = $contig->chr_start()-1;
                $slice_length = $contig->chr_end() - $contig->chr_start() + 1;
            }
        }
    }

    my $str  = emit_opening_tag('locus',0);
       $str .= emit_tagpair('stable_id', $gene->stable_id, 2);
       $str .= emit_tagpair('description', $gene->description, 2);
       $str .= emit_tagpair('type', $gene->biotype, 2);

    for my $dbentry (@{$gene->get_all_DBEntries}) {
        $str .= $dbentry->toXMLstring();
    }

    if($gene->can('gene_info')) {   # do we have an AnnotatedGene?
            # was it originally a Gene re-blessed into AnnotatedGene?
        if(my $ginfo = $gene->gene_info()) {
            $str .= $ginfo->toXMLstring();
        }
    }

    foreach my $transcript (sort by_stable_id_or_name @{$gene->get_all_Transcripts}) {
        $str .= $transcript->toXMLstring($coord_offset, $slice_length);
    }

    $str .= emit_closing_tag('locus',0);

    return $str;
}

sub Bio::EnsEMBL::Transcript::toXMLstring {
    my ($transcript, $coord_offset, $slice_length) = @_;

    my $str  = emit_opening_tag('transcript', 2);
       $str .= emit_tagpair('stable_id', $transcript->stable_id(), 4);

    if($transcript->can('transcript_info')) {   # do we have an AnnotatedTranscript?
            # was it originally a Transcript re-blessed into AnnotatedTranscript?
        if(my $tinfo = $transcript->transcript_info()) {
            $str .= $tinfo->toXMLstring();
        }
    }

    my ($tsl, $translation_ok, $tran_low, $tran_high, $tl_start, $tl_end, $tl_stable_id);
    if($tsl = $transcript->translation()) {
        my $strand = $tsl->start_Exon()->strand();

        $tran_low  = $transcript->coding_region_start;
        $tran_high = $transcript->coding_region_end;
        $translation_ok = defined($tran_low) && defined($tran_high);

        $tl_stable_id = $tsl->stable_id();
        ($tl_start, $tl_end) = ($strand == 1)
                                ? ($tran_low + $coord_offset, $tran_high + $coord_offset)
                                : ($tran_high + $coord_offset, $tran_low + $coord_offset);
    }

    EXON: foreach my $exon (@{$transcript->get_all_Exons()}) {

        # print STDERR "start=".$exon->start." end=".$exon->end." slice->length=".$slice_length."\n";
            # trimming done before sending - and we lose the translation :(
        if($exon->end()<1) { # remove from the left
            print STDERR "removing an exon because exon->end==".$exon->end()."<1\n";
            $translation_ok = 0;
            next EXON;
        } elsif($exon->start()>$slice_length) { # remove from the left
            print STDERR "removing an exon because exon->start==".$exon->start().">$slice_length==slice->length\n";
            $translation_ok = 0;
            next EXON;
        } elsif($exon->start()<1) { # trim from the left
            print STDERR "trimming an exon from the left because exon->start==".$exon->start()."<1\n";
            $exon->start(1);
            $translation_ok = 0;
        } elsif($exon->end()>$slice_length) { # trim from the right
            print STDERR "trimming an exon from the right because exon->end==".$exon->end().">$slice_length==slice->length\n";
            $exon->end($slice_length);
            $translation_ok = 0;
        }

        $str .= emit_opening_tag('exon', 4);
        $str .= emit_tagpair('stable_id', $exon->stable_id(), 6);
if($exon->start()<=0) { print STDERR "exon start is negative\n";}
        $str .= emit_tagpair('start', $exon->start() + $coord_offset, 6);
if($exon->end()<=0) { print STDERR "exon end is negative\n";}
        $str .= emit_tagpair('end', $exon->end() + $coord_offset, 6);
        $str .= emit_tagpair('strand', $exon->strand(), 6);

        # Only coding exons have frame set
        ### Do we need to test for translation region - why not
        ### just rely on phase of exon, which will be -1 if non-coding?
        if ( $translation_ok
        and $exon->start <= $tran_high
        and $tran_low <= $exon->end)
        {
            my $phase = $exon->phase;
            my $frame = $phase == -1 ? 0 : (3 - $phase) % 3;
            $str .= emit_tagpair('frame', $frame, 6);
        }

        $str .= emit_closing_tag('exon', 4);
    }

    if( $translation_ok ) {
        $str .= emit_opening_tag('translation', 4);
            $str .= emit_tagpair('start', $tl_start, 6);
            $str .= emit_tagpair('end', $tl_end, 6);
            $str .= emit_tagpair('stable_id', $tl_stable_id, 6);
        $str .= emit_closing_tag('translation', 4);
    }

    $str .= emit_closing_tag('transcript', 2);

    return $str;
}


# ----------------[inherited Bio::Otter::... classes]--------------

sub Bio::Otter::Author::toXMLstring {
    my $author = shift @_;

    # my $name  = $author->name  or $author->throw("name not set");
    # my $email = $author->email or $author->throw("email not set");

    my $str = '';
    $str .= emit_opening_tag('author', 4);
    $str .= emit_tagpair('name', $author->name(), 6);
    $str .= emit_tagpair('email', $author->email(), 6);
    $str .= emit_closing_tag('author', 4);

    return $str;
}

sub Bio::Otter::GeneInfo::toXMLstring {
    my $ginfo = shift @_;

    my $str = '';
    $str .= emit_opening_tag('gene_info', 2);

	$str .= emit_tagpair('name', $ginfo->name() && $ginfo->name()->name(), 4);
    $str .= emit_tagpair('known', $ginfo->known_flag, 4);
    $str .= emit_tagpair('truncated', $ginfo->truncated_flag, 4);

    foreach my $syn ($ginfo->synonym) {
       $str .= emit_tagpair('synonym', $syn->name() , 4);
    }

    foreach my $rem ($ginfo->remark) {
       $str .= emit_tagpair('remark', $rem->remark() , 4);
    }

    if (my $author = $ginfo->author) {
        $str .= $author->toXMLstring;
    }
    $str .= emit_closing_tag('gene_info', 2);

    return $str;
}

sub Bio::Otter::TranscriptInfo::toXMLstring {
    my $tinfo = shift @_;

    my $str = '';

    $str .= emit_opening_tag('transcript_info', 4);

    if (my $author = $tinfo->author) {
        $str .= $author->toXMLstring();
    }

    foreach my $remstr (sort map $_->remark, $tinfo->remark) {
        $remstr =~ s/\n/ /g;
        $str .= emit_tagpair('remark', $remstr, 6);
    }
	   
    foreach my $method (qw{
            cds_start_not_found
            cds_end_not_found
            mRNA_start_not_found
            mRNA_end_not_found }) {
        $str .= emit_tagpair($method, $tinfo->$method() || 0, 6);
    }

    $str .= emit_tagpair('name', $tinfo->name(), 6);
    $str .= emit_tagpair('transcript_class', $tinfo->class() && $tinfo->class()->name(), 6);

    foreach my $evidence (sort {$a->name cmp $b->name} @{$tinfo->get_all_Evidence}) {
        $str .= emit_opening_tag('evidence', 6);
        $str .= emit_tagpair('name', $evidence->name(), 8);
        $str .= emit_tagpair('name', $evidence->type(), 8);
        $str .= emit_closing_tag('evidence', 6);
    }

    $str .= emit_closing_tag('transcript_info', 4);
	    
    return $str;
}

# -----------------[misc]---------------------------------------------------

sub by_stable_id_or_name {

  my $astableid = "";
  my $bstableid = "";

  if (defined($a->stable_id)) {$astableid = $a->stable_id;}
  if (defined($b->stable_id)) {$bstableid = $b->stable_id;}
  
  my $cmpVal = ($astableid cmp $bstableid);

  if (!$cmpVal) {
    if (!defined($b->transcript_info->name) && !defined($a->transcript_info->name)) {
      $cmpVal = 0;
    } elsif (!defined($a->transcript_info->name)) {
      $cmpVal = 1;
    } elsif (!defined($b->transcript_info->name)) {
      $cmpVal = -1;
    } else {
      $cmpVal = ($a->transcript_info->name cmp $b->transcript_info->name);
    }
  }
  return $cmpVal;
}

1;
