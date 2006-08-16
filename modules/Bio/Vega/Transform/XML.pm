package Bio::Vega::Transform::XML;

use strict;

use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use base 'Bio::Vega::Writer';

sub DESTROY {
  my ($self) = @_;
  bless $self, 'Bio::Vega::Writer';
}

sub initialize {
  my ($self) = @_;
  # Register the tags that trigger the building of objects
  $self->xml_builders({gene => 'build_Genes',
							  feature => 'build_Features'});
}

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

sub build_Genes {
  my ($self, $genes) = @_;
  my $xml='';
  if($genes) {
	 
  foreach my $gene(@$genes){
	 my $pp=$self->prettyprint('locus');
	 $pp->indent(2);
	 my $gene_name_att = $gene->get_all_Attributes('name') ;
	 my $gene_name;
	 if ($gene_name_att->[0]){
		$gene_name=$gene_name_att->[0]->value;
		$pp->attribvals($self->prettyprint('name',$gene_name));
	 }
	 else {
		throw "Cannot create Otter XML, gene name is absent:$gene";
	 }
	 if ($gene->stable_id){
		$pp->attribvals($self->prettyprint('stable_id',$gene->stable_id));
	 }
	 if ($gene->biotype){
		$pp->attribvals($self->prettyprint('type',$gene->biotype));
	 }
	 my $truncated=0;
	 if ($gene->truncated_flag){
		$truncated=1;
	 }
	 $pp->attribvals($self->prettyprint('truncated',$truncated));
	 my $known=0;
	 if ($gene->is_known){
		$known=1;
	 }
	 $pp->attribvals($self->prettyprint('known',$known));
	 my $gene_author=$gene->gene_author;
	 my $author_name=$gene_author->name;
	 my $author_email=$gene_author->email;
	 if ($author_name) {
		$pp->attribvals($self->prettyprint('author',$author_name));
	 }
	 if ($author_email) {
		$pp->attribvals($self->prettyprint('author_email',$author_email));
	 }
	 if ($gene->description){
		$pp->attribvals($self->prettyprint('description',$gene->description));
	 }
	 if (my $synonyms=$gene->get_all_Attributes('synonym')){
		foreach my $syn (@$synonyms){
		  $pp->attribvals($self->prettyprint('synonym',$syn->value));
		}
	 }
	 if (my $remarks = $gene->get_all_Attributes('remark')){
		foreach my $rem (@$remarks){
		  $pp->attribvals($self->prettyprint('remark',$rem->value));
		}
	 }
	 if (my $remarks = $gene->get_all_Attributes('hidden_remark')){
		foreach my $rem (@$remarks){
		  $pp->attribvals($self->prettyprint('remark',0,$rem->value));
		}
	 }		
	 my $transcripts=$gene->get_all_Transcripts;
	 if ($transcripts) {
		foreach my $tran (@$transcripts){
		  my $t=$self->prettyprint('transcript');
		  my $tran_name_att = $tran->get_all_Attributes('name') ;
		  my $tran_name;
		  if ($tran_name_att->[0]){
			 $tran_name=$tran_name_att->[0]->value;
			 $t->attribvals($self->prettyprint('name',$tran_name));
		  }
		  else {
			 throw "Cannot create Otter XML, transcript name is absent:$tran";
		  }
		  if ($tran->stable_id) {
			 $t->attribvals($self->prettyprint('stable_id',$tran->stable_id));
		  }
		  my $tran_author=$tran->transcript_author;
		  my $author_name=$tran_author->name;
		  my $author_email=$tran_author->email;
		  if ($author_name) {
			 $t->attribvals($self->prettyprint('author',$author_name));
		  }
		  if ($author_email) {
			 $t->attribvals($self->prettyprint('author_email',$author_email));
		  }
		  if (my $translation=$tran->translation){
			 if ($translation->stable_id){
				$t->attribvals($self->prettyprint('translation_stable_id',$translation->stable_id));
			 }
			 if ($translation->start){
				$t->attribvals($self->prettyprint('translation_start',$translation->start));
			 }
			 if ($translation->end){
				$t->attribvals($self->prettyprint('translation_end',$translation->end));
			 }
		  }
		  my $mRNA_start_NF = $tran->get_all_Attributes('mRNA_start_NF') ;
		  my $mRNA_end_NF = $tran->get_all_Attributes('mRNA_end_NF') ;
		  my $cds_start_NF = $tran->get_all_Attributes('cds_start_NF') ;
		  my $cds_end_NF = $tran->get_all_Attributes('cds_end_NF') ;
		  if ($mRNA_start_NF){
			 my $msNF=$mRNA_start_NF->[0]->value;
			 $t->attribvals($self->prettyprint('mRNA_start_not_found',$msNF));
		  }
		  if ($mRNA_end_NF){
			 my $meNF=$mRNA_end_NF->[0]->value;
			 $t->attribvals($self->prettyprint('mRNA_end_not_found',$meNF));
		  }
		  if ($cds_start_NF){
			 my $csNF=$cds_start_NF->[0]->value;
			 $t->attribvals($self->prettyprint('cds_start_not_found',$csNF));
		  }
		  if ($cds_end_NF){
			 my $ceNF=$cds_end_NF->[0]->value;
			 $t->attribvals($self->prettyprint('cds_end_not_found',$ceNF));
		  }
		  ##in future <transcript_class> tag will be replaced by trancript <biotype> and <status> tags
		  ##<type> tag will be removed
		  ##don't know if <known> tag is necessary
		  if ($tran->biotype && $tran->status){
			 my $transcript_class=$self->get_transcript_class(lc($tran->biotype),$tran->status);
			 if ($transcript_class){
				$t->attribvals($self->prettyprint('transcript_class',$transcript_class));
			 }
		  }
		  my $evidence= $tran->get_Evidence;
		  if (@$evidence > 0){
			 my $es=$self->prettyprint('evidence_set');
			 foreach my $evi (@$evidence){
				my $e=$self->prettyprint('evidence');
				$e->attribvals($self->prettyprint('name',$evi->name));
				$e->attribvals($self->prettyprint('type',$evi->type));
				$es->attribobjs($e);
			 }
			 $t->attribobjs($es);
		  }
		  #else {
			# throw "Cannot create Otter XML, evidence not attached to this transcript :$tran";
		  #}
		  if (my $exon_set=$tran->get_all_Exons){
			 my $es=$self->prettyprint('exon_set');
			 foreach my $exon (@$exon_set){
				my $e=$self->prettyprint('exon');
				if ($exon->stable_id){
				  $e->attribvals($self->prettyprint('stable_id',$exon->stable_id));
				}
				if ($exon->start){
				  $e->attribvals($self->prettyprint('start',$exon->start));
				}
				else {
				  throw "Cannot create Otter XML, exon attached does not have a start, $exon , $tran";
				}
				if ($exon->end){
				  $e->attribvals($self->prettyprint('end',$exon->end));
				}
				else {
				  throw "Cannot create Otter XML, exon attached does not have a end, $exon , $tran";
				}
				if ($exon->strand){
				  $e->attribvals($self->prettyprint('strand',$exon->strand));
				}
				else {
				  throw "Cannot create Otter XML, exon attached does not have a strand, $exon , $tran";
				}
				if ($exon->frame){
				  $e->attribvals($self->prettyprint('frame',$exon->frame));
				}
				$es->attribobjs($e);
			 }
			 $t->attribobjs($es);
		  }
		  else {
			 throw "Cannot create Otter XML, no exons attched to this transcript:$tran";
		  }
		  $pp->attribobjs($t);
		}
	 }
	 else {
		throw "Cannot create Otter XML, no transcripts attched to this gene:$gene";
	 }
  $xml=$xml.$self->formatxml($pp);
  }

  }
  else {
	 return;
  }
  return $xml;
}

sub build_Features {
  my ($self, $features) = @_;
  my $pp=$self->prettyprint('feature_set');
  if($features) {
	 $pp->indent(2);
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
		  $f->attribvals($self->prettyprint('start',$feature->start));
		}
		else {
		  throw "Cannot create Otter XML, feature type is absent:$feature";
		}
		if ($feature->end){
		  $f->attribvals($self->prettyprint('end',$feature->end));
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
		$pp->attribobjs($f);
	 }
  }
  else {
	 return;
  }
  return $self->formatxml($pp);
}
1;
__END__

=head1 NAME - Bio::Vega::Transform::XML

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
