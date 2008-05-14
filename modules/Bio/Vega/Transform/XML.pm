package Bio::Vega::Transform::XML;

use strict;
use Bio::EnsEMBL::Utils::Exception qw (throw);
use base 'Bio::Vega::Writer';
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'biotype_status2method';


sub get_geneXML {
  my ($self, $gene)=@_;

  my $ppobj=$self->generate_Locus($gene,2);
  my $gene_xml=$self->formatxml($ppobj);

  return $gene_xml;
}

sub generate_OtterXML {
  my ($self, $slices, $odb, $indent, $genes, $sf)=@_;

  my $ot=$self->prettyprint('otter');
  $ot->indent($indent);
  foreach my $slice (@$slices){
	 $ot->attribobjs($self->generate_SequenceSet($slice, $odb, $genes,$sf));
  }
  return $self->formatxml($ot);
}

sub generate_SequenceSet {
  my ($self, $slice, $odb, $genes, $features)=@_;

  my $ss=$self->prettyprint('sequence_set');
  $ss->attribvals($self->generate_AssemblyType($slice));

  my $slice_projection = $slice->project('contig');
  foreach my $contig_seg (@$slice_projection) {
	 $ss->attribobjs($self->generate_SequenceFragment($contig_seg, $slice, $odb));
  }

  $features ||= $slice->get_all_SimpleFeatures;

  # Now it is very important that we discard features that intersect the slice boundaries:

    for (my $i = 0; $i < @$features; ) {
        my $sf = $features->[$i];
        if( ($sf->start()<1) || ($sf->end()>$slice->length()) ) {
            splice(@$features, $i, 1);
        } else {
            $i++;
        }
    }
  
  $ss->attribobjs($self->generate_FeatureSet($features,$slice));

  $genes ||= $slice->get_all_Genes;
  foreach my $gene(@$genes){
	 $ss->attribobjs($self->generate_Locus($gene));
  }
  return $ss;
}


sub generate_AssemblyType {
    my ($self, $slice)=@_;

    my $atype=$self->prettyprint('assembly_type', $slice->seq_region_name);

    return $atype;
}

sub generate_SequenceFragment {
    my ($self, $contig_seg, $slice, $odb)=@_;

    my $sf = $self->prettyprint('sequence_fragment');
    my $contig_slice = $contig_seg->to_Slice();

    if($contig_slice->seq_region_name) {
        $sf->attribvals($self->prettyprint('id',$contig_slice->seq_region_name));
    }

    if( my $chrs = $slice->get_all_Attributes('chr') ) {
        if(@$chrs > 1) {
            throw("Chromosome Slice: $slice has more than one value for name attrib, cannot generate xml");
        }
        my $chr_name = $chrs->[0] && $chrs->[0]->value;
        $sf->attribvals($self->prettyprint('chromosome', $chr_name));
    }

    my ($clone_seg) = @{ $contig_slice->project('clone') };
    my $clone_slice = $clone_seg->to_Slice();

    my ($acc_name, $ver, $clone_name);
    if( my $accs = $clone_slice->get_all_Attributes('embl_acc') ) {
        if (@$accs > 1){
            throw("Clone Slice:$clone_slice has more than one value for accession attrib, cannot generate xml");
        }

        $acc_name = $accs->[0] && $accs->[0]->value;
        $sf->attribvals($self->prettyprint('accession',$acc_name));
    } else {
        throw("Missing clone accession, cannot generate xml:$clone_slice");
    }

    if( my $vers = $clone_slice->get_all_Attributes('embl_version') ) {
        if (@$vers > 1){
            throw("Clone Slice:$clone_slice has more than one value for version attrib, cannot generate xml");
        }

        $ver = $vers->[0] && $vers->[0]->value;
        $sf->attribvals($self->prettyprint('version',$ver));
    } else {
        throw("Missing clone version, cannot generate xml:$clone_slice");
    }

    if( my $clnames = $clone_slice->get_all_Attributes('intl_clone_name') ) {
        if (@$clnames > 1){
            throw("Clone Slice:$clone_slice has more than one value for intl_clone_name attrib, cannot generate xml");
        }

        $clone_name = ($clnames->[0] && $clnames->[0]->value) || $acc_name. '.' .$ver
    } else {
        $clone_name = $acc_name. '.' .$ver ;
    }
    $sf->attribvals($self->prettyprint('clone_name',$clone_name));

    my $ci = $odb->get_ContigInfoAdaptor->fetch_by_contigSlice($contig_slice);

    my $author_name;
    my $author_email;
    if(my $contig_author = $ci && $ci->author) {
        $author_name  = $contig_author->name;
        $author_email = $contig_author->email;
    }
    $sf->attribvals($self->prettyprint('author', $author_name));
    $sf->attribvals($self->prettyprint('author_email', $author_email));

    if($ci) {
	    my $ci_attribs = $ci->get_all_Attributes;

        foreach my $cia (@$ci_attribs) {
            if ($cia->code eq 'remark'
            || $cia->code eq 'hidden_remark'
            || $cia->code eq 'annotated'
            || $cia->code eq 'description') {
                my $value = $cia->value;

                if ($cia->code eq 'description') {
                    $value = 'EMBL_dump_info.DE_line- ' . $value;
                }
                if ($cia->code eq 'annotated' && $cia->value eq 'T') {
                    $value = 'Annotation_remark- annotated';
                }
                $sf->attribvals($self->prettyprint('remark', $value));
            }
        }
        foreach my $cia (@$ci_attribs) {
            if ($cia->code eq 'keyword') {
                $sf->attribvals($self->prettyprint('keyword',$cia->value));
            }
        }
    }

    my $assembly_offset = $slice->start() - 1;
    $sf->attribvals($self->prettyprint('assembly_start',$contig_seg->from_start + $assembly_offset));
    $sf->attribvals($self->prettyprint('assembly_end',  $contig_seg->from_end   + $assembly_offset));

    if ($contig_slice->strand) {
        $sf->attribvals($self->prettyprint('fragment_ori',$contig_slice->strand));
    } else {
        throw("Missing fragment orientation, cannot generate xml:$contig_slice");
    }
    if ($contig_slice->start) {
        $sf->attribvals($self->prettyprint('fragment_offset',$contig_slice->start));
    } else {
        throw("Missing fragment offset, cannot generate xml:$contig_slice");
    }
    if( my $clone_length = $clone_slice->seq_region_length()) {
        $sf->attribvals($self->prettyprint('clone_length',$clone_length));
    } else {
        throw("Missing clone length, cannot generate xml:$clone_slice");
    }

    return $sf;
}

sub generate_Locus {
    my ($self, $gene, $indent) = @_;

    return unless $gene;

    my $g=$self->prettyprint('locus');
    if (defined $indent) {
        $g->indent($indent);
    }

    if($gene->stable_id) {
        $g->attribvals($self->prettyprint('stable_id',$gene->stable_id));
    }

    my $gene_description = $gene->description || '';
    $g->attribvals($self->prettyprint('description', $gene_description));

    my $gene_name_att = $gene->get_all_Attributes('name');
    my $gene_name = $gene_name_att->[0] ? $gene_name_att->[0]->value : '';
    $g->attribvals($self->prettyprint('name', $gene_name));

    my ($type) = biotype_status2method($gene->biotype, $gene->status);
    my $source = $gene->source;
    if ($source ne 'havana') {
        $type = "$source:$type";
    }
    $g->attribvals($self->prettyprint('type',$type));

    $g->attribvals($self->prettyprint('known',$gene->is_known || 0));
    $g->attribvals($self->prettyprint('truncated',$gene->truncated_flag));

    if(my $synonyms = $gene->get_all_Attributes('synonym')) {
        foreach my $syn (@$synonyms){
            $g->attribvals($self->prettyprint('synonym',$syn->value));
        }
    }

    if(my $remarks = $gene->get_all_Attributes('remark')) {
        foreach my $rem (@$remarks) {
            $g->attribvals($self->prettyprint('remark',$rem->value));
        }
    }
    if(my $remarks = $gene->get_all_Attributes('hidden_remark')) {
        foreach my $rem (@$remarks) {
            $g->attribvals($self->prettyprint('remark','Annotation_remark- '.$rem->value));
        }
    }

    my $author_name;
    my $author_email;
    if( my $gene_author=$gene->gene_author ) {
        $author_name  = $gene_author->name;
        $author_email = $gene_author->email;
    }
    $g->attribvals($self->prettyprint('author', $author_name));
    $g->attribvals($self->prettyprint('author_email', $author_email));

    if( my $transcripts=$gene->get_all_Transcripts ) {

        my $coord_offset=$gene->get_all_Exons->[0]->slice->start-1;

        foreach my $tran (@$transcripts){
            $g->attribobjs($self->generate_Transcript($tran, $coord_offset));
        }
    } else {
        throw "Cannot create Otter XML, no transcripts attched to this gene:$gene";
    }

    return $g;
}

sub generate_Transcript {
    my ($self, $tran, $coord_offset)=@_;

    my $t=$self->prettyprint('transcript');
    if($tran->stable_id) {
        $t->attribvals($self->prettyprint('stable_id',$tran->stable_id));
    }

    my $author_name;
    my $author_email;
    if( my $transcript_author=$tran->transcript_author ) {
        $author_name  = $transcript_author->name;
        $author_email = $transcript_author->email;
    }
    $t->attribvals($self->prettyprint('author',$author_name));
    $t->attribvals($self->prettyprint('author_email',$author_email));

  if(my $remarks = $tran->get_all_Attributes('remark')){
     foreach my $rem (@$remarks){
        $t->attribvals($self->prettyprint('remark',$rem->value));
     }
  }
  if(my $remarks = $tran->get_all_Attributes('hidden_remark')){
	 foreach my $rem (@$remarks){
		$t->attribvals($self->prettyprint('remark','Annotation_remark- '.$rem->value));
	 }
  }

  my $mRNA_start_NF = $tran->get_all_Attributes('mRNA_start_NF') ;
  my $mRNA_end_NF = $tran->get_all_Attributes('mRNA_end_NF') ;
  my $cds_start_NF = $tran->get_all_Attributes('cds_start_NF') ;
  my $cds_end_NF = $tran->get_all_Attributes('cds_end_NF') ;
  if (defined $cds_start_NF){
	 my $csNF=$cds_start_NF->[0]->value;
	 $t->attribvals($self->prettyprint('cds_start_not_found',$csNF));
  }
  if (defined $cds_end_NF){
	 my $ceNF=$cds_end_NF->[0]->value;
	 $t->attribvals($self->prettyprint('cds_end_not_found',$ceNF));
  }
  if (defined $mRNA_start_NF){
	 my $msNF=$mRNA_start_NF->[0]->value;
	 $t->attribvals($self->prettyprint('mRNA_start_not_found',$msNF));
  }
  if (defined $mRNA_end_NF){
	 my $meNF=$mRNA_end_NF->[0]->value;
	 $t->attribvals($self->prettyprint('mRNA_end_not_found',$meNF));
  }
  ##in future <transcript_class> tag will be replaced by trancript <biotype> and <status> tags
  ##<type> tag will be removed
  my ($class) = biotype_status2method($tran->biotype, $tran->status);
  $t->attribvals($self->prettyprint('transcript_class', $class));

  my $tran_name_att = $tran->get_all_Attributes('name') ;
  my $tran_name='';
  if ($tran_name_att->[0]){
	 $tran_name=$tran_name_att->[0]->value;
  }
  $t->attribvals($self->prettyprint('name',$tran_name));

  my $es=$self->generate_EvidenceSet($tran);
  if ($es) {
	 $t->attribobjs($es);
  }

  my ($tran_low,$tran_high);
  if (my $translation=$tran->translation){
	 my $strand = $translation->start_Exon->strand;
	 $tran_low  = $tran->coding_region_start;
	 $tran_high = $tran->coding_region_end;
	 my ($tl_start, $tl_end) = ($strand == 1)
		? ($tran_low + $coord_offset, $tran_high + $coord_offset)
		  : ($tran_high + $coord_offset, $tran_low + $coord_offset);
	 if ($tl_start){
		$t->attribvals($self->prettyprint('translation_start',$tl_start));
	 }
	 if ($tl_end){
		$t->attribvals($self->prettyprint('translation_end',$tl_end));
	 }
	 if ($translation->stable_id){
		$t->attribvals($self->prettyprint('translation_stable_id',$translation->stable_id));
	 }

  }

  $t->attribobjs($self->generate_ExonSet($tran,$coord_offset, $tran_low, $tran_high));

  return $t;
}


sub generate_ExonSet {
  my ($self,$tran,$coord_offset,$tran_low, $tran_high)=@_;

  my $exon_set=$tran->get_all_Exons;
  my $exs=$self->prettyprint('exon_set');
  foreach my $exon (@$exon_set){
	 my $e=$self->prettyprint('exon');
     if($exon->stable_id) {
         $e->attribvals($self->prettyprint('stable_id',$exon->stable_id));
     }
	 $e->attribvals($self->prettyprint('start',$exon->start + $coord_offset));
	 $e->attribvals($self->prettyprint('end',$exon->end  + $coord_offset));
	 $e->attribvals($self->prettyprint('strand',$exon->strand));
	 if ( defined($tran_high) && $exon->start <= $tran_high &&
         defined($tran_low)  && $tran_low <= $exon->end){
		my $phase = $exon->phase;
		my $frame = $phase == -1 ? 0 : (3 - $phase) % 3;
		$e->attribvals($self->prettyprint('frame',$frame));
	 }
	 $exs->attribobjs($e);
  }
  return $exs;
}


sub generate_EvidenceSet {
  my ($self,$tran)=@_;

  my $evidence=$tran->evidence_list();
  my $es=$self->prettyprint('evidence_set');
  foreach my $evi (@$evidence){
	 my $e=$self->prettyprint('evidence');
	 $e->attribvals($self->prettyprint('name',$evi->name));
	 $e->attribvals($self->prettyprint('type',$evi->type));
	 $es->attribobjs($e);
  }
  my $c = $evidence ? scalar(@$evidence) : 0;

  if ($c>0){
	 return $es;
  } else {
	 return;
  }
}

sub generate_FeatureSet {
  my ($self, $features,$slice) = @_;

  return unless $features;

  my $fs=$self->prettyprint('feature_set');
  my $offset=$slice->start-1;

  foreach my $feature(@$features){

	 my $f = $self->prettyprint('feature');
	 if ($feature->analysis){
		my $a=$feature->analysis;
		$f->attribvals($self->prettyprint('type',$a->logic_name));
	 } else {
		throw "Cannot create Otter XML, feature type is absent: $feature";
	 }

	 if ($feature->start){
		$f->attribvals($self->prettyprint('start',$feature->start+$offset));
	 } else {
		throw "Cannot create Otter XML, feature start is absent: $feature";
	 }

	 if ($feature->end){
		$f->attribvals($self->prettyprint('end',$feature->end+$offset));
	 } else {
		throw "Cannot create Otter XML, feature end is absent: $feature";
	 }

	 if ($feature->strand){
		$f->attribvals($self->prettyprint('strand',$feature->strand));
	 } else {
		throw "Cannot create Otter XML, feature strand is absent: $feature";
	 }

	 if ($feature->score){
		$f->attribvals($self->prettyprint('score',$feature->score));
	 }
	 if ($feature->display_label){
		$f->attribvals($self->prettyprint('label',$feature->display_label));
	 }
	 $fs->attribobjs($f);
  }
  return ($fs);
}


sub generate_DNA {
    my ($self, $slice);

    my $dna=$self->prettyprint('dna', $slice->seq);

    return $dna;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::XML

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

