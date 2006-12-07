package Bio::Vega::Transform::XML;

use strict;
use Bio::Vega::Utils::XmlEscape qw (xml_escape);
use Bio::EnsEMBL::Utils::Exception qw ( throw);
use base 'Bio::Vega::Writer';


sub get_transcript_class {
  my ($self,$biotype,$status)=@_;
  my $transcript_class_mapping = { "UNKNOWN" => {'unprocessed_pseudogene'=>'Unprocessed_pseudogene',
															'processed_pseudogene'=>'Processed_pseudogene',
															'pseudogene'=>'Pseudogene',
															'Ig_pseudogene_segment'=>'Ig_pseudogene_segment',
															'coding'=>'Coding',
															},
											  "KNOWN" => {'protein_coding'=>'Known'},
											  "NOVEL" => {'protein_coding'=>'Novel_CDS',
															  'Ig_segment'=>'Ig_segment',
															  'processed_transcript'=>'Novel_transcript',
															 },
											  "PUTATIVE" => {'processed_transcript'=>'Putative',
																 },
											  "PREDICTED"=>{'protein_coding'=>'Predicted_gene',
																}
											};

  return $transcript_class_mapping->{$status}->{$biotype};
}

sub generate_OtterXML{
  my ($self,$slices,$odb,$indent,$genes,$sf)=@_;
  my $ot=$self->prettyprint('otter');
  $ot->indent($indent);
  foreach my $slice (@$slices){
	 $ot->attribobjs($self->generate_SequenceSet($slice,$odb,$genes,$sf));
  }
  return $self->formatxml($ot);
}

sub generate_SequenceSet{
  my ($self,$slice,$odb,$genes,$features)=@_;
  my $ss=$self->prettyprint('sequence_set');
  $ss->attribvals($self->generate_AssemblyType($slice));
  my $slice_projection = $slice->project('contig');
  foreach my $contig_seg (@$slice_projection) {
	 $ss->attribobjs($self->generate_SequenceFragment($contig_seg,$slice,$odb));
  }
  my $sfa = $odb->get_SimpleFeatureAdaptor();
  unless ($features) {
	 $features = $slice->get_all_SimpleFeatures;
  }
  $ss->attribobjs($self->generate_FeatureSet($features,$slice));
  my $ga=$odb->get_GeneAdaptor;
  unless ($genes){
  $genes=$slice->get_all_Genes;
  }
  foreach my $gene(@$genes){
	 $ss->attribobjs($self->generate_Locus($gene));
  }
  return $ss;
}


sub generate_AssemblyType{
   my ($self,$slice)=@_;
	my $at=$self->prettyprint('assembly_type',$slice->seq_region_name);
	return $at;
}

sub generate_SequenceFragment{
  my ($self,$contig_seg,$slice,$odb)=@_;
  my $assembly_offset = $slice->start()-1;
  my $sf = $self->prettyprint('sequence_fragment');
  my $contig_slice = $contig_seg->to_Slice();
  my ($clone_seg) = @{ $contig_slice->project('clone') };
  my $clone_slice = $clone_seg->to_Slice();
  my $chrs = $slice->get_all_Attributes('chr');
  my $chr_name;
  if ($contig_slice->seq_region_name){
	 $sf->attribvals($self->prettyprint('id',$contig_slice->seq_region_name));
  }

  if ($chrs) {
	 if (@$chrs > 1){
		throw("Chromosome Slice:$slice has more than one value for name attrib, cannot generate xml");
	 }
	 if ($chrs->[0]){
		$chr_name=$chrs->[0]->value;
	 }
	 $sf->attribvals($self->prettyprint('chromosome',$chr_name));
  }
  my $accs=$clone_slice->get_all_Attributes('embl_acc');
  if ($accs) {
	 if (@$accs > 1){
		throw("Clone Slice:$clone_slice has more than one value for accession attrib, cannot generate xml");
	 }
	 if ($accs->[0]){
		my $acc_name=$accs->[0]->value;
		$sf->attribvals($self->prettyprint('accession',$acc_name));
	 }
  }
  else {
	 throw("Missing clone accession, cannot generate xml:$clone_slice");
  }
  my $vers=$clone_slice->get_all_Attributes('embl_version');
  if ($vers) {
	 if (@$vers > 1){
		throw("Clone Slice:$clone_slice has more than one value for version attrib, cannot generate xml");
	 }
	 if ($vers->[0]){
		my $ver=$vers->[0]->value;
		$sf->attribvals($self->prettyprint('version',$ver));
	 }
  }
  else {
	 throw("Missing clone version, cannot generate xml:$clone_slice");
  }
  my $cia=$odb->get_ContigInfoAdaptor;
  my $contig_slice_dbid=$contig_slice->get_seq_region_id;
  my $ci=$cia->fetch_by_seq_region_id($contig_slice_dbid);
  my $auth=$ci->author;
  my $auth_name=$auth->name;
  my $auth_email=$auth->email;
  $sf->attribvals($self->prettyprint('author',$auth_name));
  $sf->attribvals($self->prettyprint('author_email',$auth_email));
  my $ci_attribs=$ci->get_all_Attributes;
  foreach my $cia (@$ci_attribs){
	 if ($cia->code eq 'remark' || $cia->code eq 'hidden_remark' || $cia->code eq 'annotated' || $cia->code eq 'description'){
		if ($cia->code eq 'annotated' && $cia->value eq 'T'){
		  $cia->value('Annotation_remark- annotated');
		}
		if ($cia->code eq 'description') {
		  $cia->value("EMBL_dump_info.DE_line- ".$cia->value);
		}
		xml_escape($cia->value);
		$sf->attribvals($self->prettyprint('remark',$cia->value));
	 }
  }
  foreach my $cia (@$ci_attribs){
	 if ($cia->code eq 'keyword'){
		$sf->attribvals($self->prettyprint('keyword',$cia->value));
	 }
  }


  $sf->attribvals($self->prettyprint('assembly_start',$contig_seg->from_start + $assembly_offset));
  $sf->attribvals($self->prettyprint('assembly_end',  $contig_seg->from_end   + $assembly_offset));
  if ($contig_slice->strand){
	 $sf->attribvals($self->prettyprint('fragment_ori',$contig_slice->strand));
  }
  else {
	 throw("Missing fragment orientation, cannot generate xml:$contig_slice");
  }
  if ($contig_slice->start){
	 $sf->attribvals($self->prettyprint('fragment_offset',$contig_slice->start));
  }
  else {
	 throw("Missing fragment offset, cannot generate xml:$contig_slice");
  }

  return $sf;
}

sub generate_Locus {
  my ($self, $gene) = @_;
  return unless $gene;
  my $g=$self->prettyprint('locus');
  $g->attribvals($self->prettyprint('stable_id',$gene->stable_id));
  my $gene_description='';
  if ($gene->description){
	 $gene_description=$gene->description;
  }
  xml_escape($gene_description);
  $g->attribvals($self->prettyprint('description',$gene_description));
  my $gene_name_att = $gene->get_all_Attributes('name') ;
  my $gene_name='';
  if ($gene_name_att->[0]){
	 $gene_name=$gene_name_att->[0]->value;
  }
  $g->attribvals($self->prettyprint('name',$gene_name));
  my $gene_biotype=$gene->biotype;
  my $gene_status=$gene->status;
  my $gene_source=$gene->source;
  my $type=$self->get_transcript_class(lc($gene_biotype),$gene_status);
  unless ($type){
	 $type=$gene_biotype;
  }
  my $source;
  if ($gene_source ne 'havana'){
	 $source=$gene_source;
	 $type=$source.':'.$type;
  }
  $g->attribvals($self->prettyprint('type',$type));
  my $known=0;
  if ($gene->is_known){
	 $known=1;
  }
  $g->attribvals($self->prettyprint('known',$known));
  my $truncated=0;
  if ($gene->truncated_flag){
	 $truncated=1;
  }
  $g->attribvals($self->prettyprint('truncated',$truncated));
  if (my $synonyms=$gene->get_all_Attributes('synonym')){
	 foreach my $syn (@$synonyms){
		$g->attribvals($self->prettyprint('synonym',$syn->value));
	 }
  }
  if (my $remarks = $gene->get_all_Attributes('remark')){
	 foreach my $rem (@$remarks){
		xml_escape($rem->value);
		$g->attribvals($self->prettyprint('remark',$rem->value));
	 }
  }
  if (my $remarks = $gene->get_all_Attributes('hidden_remark')){
	 foreach my $rem (@$remarks){
		xml_escape($rem->value);
		$g->attribvals($self->prettyprint('remark',0,$rem->value));
	 }
  }
  my $gene_author=$gene->gene_author;
  my $author_name='';
  my $author_email='';
  if ($gene_author) {
	 $author_name=$gene_author->name;
	 $author_email=$gene_author->email;
  }
  $g->attribvals($self->prettyprint('author',$author_name));
  $g->attribvals($self->prettyprint('author_email',$author_email));
  my $exons=$gene->get_all_Exons;
  my $coord_offset=$exons->[0]->slice->start-1;
  my $transcripts=$gene->get_all_Transcripts;
  if ($transcripts) {
	 foreach my $tran (@$transcripts){
		$g->attribobjs($self->generate_Transcript($tran,$coord_offset));
	 }
  }
  else {
	 throw "Cannot create Otter XML, no transcripts attched to this gene:$gene";
  }
  return $g;
}

sub generate_Transcript{

  my ($self,$tran,$coord_offset)=@_;
  my $t=$self->prettyprint('transcript');
  my $tran_stable_id='';
  if ($tran->stable_id) {
	 $tran_stable_id=$tran->stable_id;
  }
  $t->attribvals($self->prettyprint('stable_id',$tran_stable_id));
  my $tran_author=$tran->transcript_author;
  my $author_name='';
  my $author_email='';
  if ($tran_author){
	 $author_name=$tran_author->name;
	 $author_email=$tran_author->email;
  }
  $t->attribvals($self->prettyprint('author',$author_name));
  $t->attribvals($self->prettyprint('author_email',$author_email));
  my $tran_remark_att = $tran->get_all_Attributes('remark') ;
  foreach my $r (@$tran_remark_att){
	 xml_escape($r->value);
	 $t->attribvals($self->prettyprint('remark',$r->value));
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
  ##don't know if <known> tag is necessary
  if ($tran->biotype && $tran->status){
	 #my $transcript_class='';
	 my $transcript_class=$self->get_transcript_class(lc($tran->biotype),$tran->status);
	 unless ($transcript_class) {
		if ($tran->biotype){
		  $transcript_class=$tran->biotype;
		}
	 }
	 if ($transcript_class){
		$t->attribvals($self->prettyprint('transcript_class',$transcript_class));
	 }
  }

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


sub generate_ExonSet{
  my ($self,$tran,$coord_offset,$tran_low, $tran_high)=@_;
  my $exon_set=$tran->get_all_Exons;
  my $exs=$self->prettyprint('exon_set');
  foreach my $exon (@$exon_set){
	 my $e=$self->prettyprint('exon');
	 $e->attribvals($self->prettyprint('stable_id',$exon->stable_id));
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


sub generate_EvidenceSet{
  my ($self,$tran)=@_;
  my $evidence=$tran->get_Evidence;
  my $es=$self->prettyprint('evidence_set');
  foreach my $evi (@$evidence){
	 my $e=$self->prettyprint('evidence');
	 $e->attribvals($self->prettyprint('name',$evi->name));
	 $e->attribvals($self->prettyprint('type',$evi->type));
	 $es->attribobjs($e);
  }
  my $c=0;
  if ($evidence){
	 $c=@$evidence;
  }

  if ($c>0){
	 return $es;
  }
  else {
	 return;
  }
}

sub generate_FeatureSet {
  my ($self, $features,$slice) = @_;
  return unless $features;
  my $offset=$slice->start-1;
  my $fs=$self->prettyprint('feature_set');
  foreach my $feature(@$features){
	 my $f = $self->prettyprint('feature');
	 if ($feature->analysis){
		my $a=$feature->analysis;
		$f->attribvals($self->prettyprint('type',$a->logic_name));
	 }
	 else {
		throw "Cannot create Otter XML, feature type is absent:$feature";
	 }
	 if ($feature->start){
		$f->attribvals($self->prettyprint('start',$feature->start+$offset));
	 }
	 else {
		throw "Cannot create Otter XML, feature type is absent:$feature";
	 }
	 if ($feature->end){
		$f->attribvals($self->prettyprint('end',$feature->end+$offset));
	 }
	 else {
		throw "Cannot create Otter XML, feature type is absent:$feature";
	 }
	 if ($feature->strand){
		$f->attribvals($self->prettyprint('strand',$feature->strand));
	 }
	 else {
		throw "Cannot create Otter XML, feature type is absent:$feature";
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
  my ($self,$slice);
  my $dna=$slice->seq;
  my $d=$self->prettyprint('dna',$dna);
  return $d;
}


1;
__END__

=head1 NAME - Bio::Vega::Transform::XML

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
