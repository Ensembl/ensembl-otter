
### Bio::Vega::Transform::Otter

package Bio::Vega::Transform::Otter;

use strict;
use Carp;
use Bio::EnsEMBL::Exon;
use Bio::Vega::Transcript;
use Bio::Vega::Gene;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch;
use Bio::EnsEMBL::Attribute;
use Bio::Vega::Author;
use Bio::Vega::AuthorGroup;
use Bio::Vega::ContigInfo;
use Bio::Vega::Evidence;

use Data::Dumper;   # For debugging
# This misses the "$VAR1 = " bit out from the Dumper() output
$Data::Dumper::Terse = 1;

use base 'Bio::Vega::Transform';

my (
    %exon_list,
	 %evidence_list,
    %gene_list,
    %transcript_list,
    %feature_list,
	 %logic_ana,
	 %coord_system,
	 %slice,
	 %time_now,
	 %biotype_status_mapping,
	 %seen_transcript_name,
	 %seen_gene_name,
	 %sequence_set,
    );


sub DESTROY {
  my ($self) = @_;
  delete $exon_list{$self};
  delete $evidence_list{$self};
  delete $gene_list{$self};
  delete $transcript_list{$self};
  delete $feature_list{$self};
  delete $logic_ana{$self};
  delete $coord_system{$self};
  delete $slice{$self};
  delete $time_now{$self};
  delete $biotype_status_mapping{$self};
  delete $seen_gene_name{$self};
  delete $seen_transcript_name{$self};
  delete $sequence_set{$self};
  # So that DESTROY gets called in baseclass:
  bless $self, 'Bio::Vega::Transform';
}

##initialize the parser with methods

sub initialize {
  my ($self) = @_;
  # Register the tags that trigger the building of objects
  $self->object_builders(
								 {
								  exon                => 'build_Exon',
								  transcript          => 'build_Transcript',
								  locus               => 'build_Locus',
								  evidence            => 'build_Evidence',
								  feature             => 'build_Feature',
								  assembly_tag        => 'build_AssemblyTag',
								  sequence_fragment   => 'build_SequenceFragment',
								  assembly_type        => 'build_AssemblyType',
								  # We don't currently do anything on encountering
								  # these end tags:
								  exon_set            => 'report_set_end',
								  evidence_set        => 'report_set_end',
								  feature_set   => 'report_set_end',
								  otter         => 'report_set_end',
								 }
								  );
  $self->set_multi_value_tags(
										[
										 [ locus             => qw{ remark synonym } ],
										 [ transcript        => qw{ remark         } ],
										 [ sequence_fragment => qw{ remark keyword } ],
										]
									  );
  $self->init_builders(
							  {
								otter                  => 'init_CoordSystem_Version',
								vega                   => 'init_CoordSystem_Version',
							  }
							 );
  $biotype_status_mapping{$self}= 
	 {'unprocessed_pseudogene' => ['unprocessed_pseudogene','UNKNOWN'],
	  'processed_pseudogene' => ['processed_pseudogene' ,'UNKNOWN'],
	  'pseudogene' => ['pseudogene' ,'UNKNOWN'],
	  'novel_transcript' => ['processed_transcript' ,'NOVEL'],
	  'known' => ['protein_coding' ,'KNOWN'],
	  'novel_cds' => ['protein_coding' ,'NOVEL'],
	  'putative' => ['processed_transcript' ,'PUTATIVE'],
	  'predicted_gene' => ['protein_coding' ,'PREDICTED'],
	  'ig_pseudogene_segment' => ['Ig_pseudogene_segment' ,'UNKNOWN'],
	  'ig_segment' => ['Ig_segment' ,'NOVEL'],
	 };
  $time_now{$self}=time;
}

sub init_CoordSystem_Version {
  my ($self,$value)=@_;
  $coord_system{$self}{'version'} ||= $value;
  return $coord_system{$self}{'version'};
}

## parser builder methods to build otter objects

sub build_SequenceFragment {
  my ($self, $data) = @_;
  my $cln_coord_system=$self->make_CoordSystem('clone');
  my $ctg_coord_system=$self->make_CoordSystem('contig');
  my $chr_coord_system=$self->make_CoordSystem('chromosome');
  my $chrname=$sequence_set{$self}{'chrname'};
  my $chr_slice_name=$sequence_set{$self}{'assembly_type'};
  if (!defined $chr_slice_name) {
	 die "cannot make chromosome slice without assembly type name\n";
  }
  if (!defined $chrname) {
	 $chrname=$data->{'chromosome'};
	 $sequence_set{$self}{'chrname'}=$data->{'chromosome'};
  }
  else {
	 if ( $chrname ne $data->{'chromosome'}) {
		die " Chromosome names are different - can't make slice [$chrname][".$data->{'chromosome'}."]\n";
	 }
  }
  my $offset = $data->{'fragment_offset'};
  my $start  = $data->{'assembly_start'};
  my $end    = $data->{'assembly_end'};
  my $strand = $data->{'fragment_ori'};
  my $chrslice=$self->get_ChromosomeSlice;
  unless ($chrslice) {
	 $chrslice = make_Slice($self,$chr_slice_name,1,$end,$end,1,$chr_coord_system);
	 $slice{$self}{'chr'} ||= $chrslice;
	 my $chr_attrib=$self->make_Attribute('chr','Chromosome Name','Chromosome Name Contained in the Assembly',$data->{'chromosome'});
	 my $chr_attrib_list = $slice{$self}{'chr_attrib'} ||= [];
	 push @$chr_attrib_list,$chr_attrib;
  }
  else {
	 $chrslice=$slice{$self}{'chr'};
	 my $slice_start=$chrslice->start();
#	 if ( $start < $slice_start ) {
	#	$slice_start=$start;
	 #}
	 my $slice_end=$chrslice->end();
	 if ( $end > $slice_end ) {
		$slice_end=$end;
	 }
	 unless ($chrname and $start and $end and $offset and $strand) {
		die "XML does not contain information needed to create slice:\nchr name='$chrname'  chr start='$start'  chr end='$end' offset='$offset' strand = '$strand'";
	 }
#	 my $new_chr_slice=make_Slice($self,$chr_slice_name,$slice_start,$slice_end,$slice_end,1,$chr_coord_system);
	 my $new_chr_slice=make_Slice($self,$chr_slice_name,1,$slice_end,$slice_end,1,$chr_coord_system);
	 $slice{$self}{'chr'}=$new_chr_slice;
  }
  my $cmp_start = $offset;
  my $cmp_end = $offset + $end - $start;
  my $ctg_id=$data->{'id'};
  my $cln_length;
  if ($ctg_id =~ /\S+\.\d+\.\d+\.(\d+)/){
	 $cln_length=$1;
  }
  if (!defined($start || $end || $strand || $offset || $ctg_id) ) {
	 die "ERROR: Either start:$start or end:$end or strand:$strand or offset:$offset or contig_id:$ctg_id not defined in the xml file\n";
  }
  my $accession = $data->{'accession'};
  my $version = $data->{'version'};
  my $cln_name = "$accession".".$version";
  ##make clone - contig slice
  my $cln_slice = $self->make_Slice($cln_name,1,$cln_length,$cln_length,$strand,$cln_coord_system);
  my $ctg_slice = $self->make_Slice($ctg_id,1,$cln_length,$cln_length,$strand,$ctg_coord_system);
  ## make clone-info attributes from remark and keyword
  my $cln_attrib;
  my $cln_attrib_list=[];
  my $remarks=$data->{'remark'};
  foreach my $rem (@$remarks){
	 if ($rem =~ /EMBL_dump_info.DE_line-\s+(.+)/) {
		$cln_attrib=$self->make_Attribute('description','EMBL Header Description','',$1);
	 }
	 elsif ($rem =~ /Annotation_remark-\s+(.+)/) {
		$rem=$1;
		if ($rem =~ /annotated/){
		  $rem=$1;
		  $cln_attrib=$self->make_Attribute('annotated','Clone Annotation Status','','T');
		}
		else {
		  $cln_attrib=$self->make_Attribute('hidden_remark','Hidden Remark','',$rem);
		}
	 }
	 else {
		$cln_attrib=$self->make_Attribute('remark','Remark','Annotation Remark',$rem);
	 }
	 push @$cln_attrib_list,$cln_attrib;
  }
  my $keywords=$data->{'keyword'};
  foreach my $key (@$keywords) {
	 $cln_attrib=$self->make_Attribute('keyword','Clone Keyword','',$key);
	 push @$cln_attrib_list,$cln_attrib;
  }
  ##in future a group_name tag is required
  my $cln_author=$self->make_Author($data->{'author'},$data->{'author_email'},'');
  my $cln_ctg_piece=[$cln_slice,$ctg_slice];
  my $cln_ctg_list = $slice{$self}{'cln_ctg'} ||= [];
  push @$cln_ctg_list,$cln_ctg_piece;
  ##make chromosome - contig slice
  my $chr_asm_slice = $self->make_Slice($chr_slice_name,$start,$end,$end,$strand,$chr_coord_system);
  my $ctg_cmp_slice = $self->make_Slice($ctg_id,$cmp_start,$cmp_end,$cmp_end,$strand,$ctg_coord_system);
  my $chr_ctg_piece = [$chr_asm_slice,$ctg_cmp_slice,$cln_attrib_list,$cln_author];
  my $chr_ctg_list = $slice{$self}{'chr_ctg'} ||= [];
  push @$chr_ctg_list,$chr_ctg_piece;
}


sub build_Evidence {
  my ($self, $data) = @_;
  my $evidence = Bio::Vega::Evidence->new(
														-name     => $data->{'name'},
														-type       => $data->{'type'},
													  );
  my $list = $evidence_list{$self} ||= [];
  push @$list, $evidence;
}


sub build_Feature {
  my ($self, $data) = @_;
  my $ana = $logic_ana{$self}{$data->{'type'}} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $data->{'type'});
  my $slice = $self->get_ChromosomeSlice;
  # convert xml coordinates which are in chromosomal coords - to feature coords
  my $offset = 1 - $slice->start ;
  my $feat_start = $data->{'start'} + $offset;
  my $feat_end =  $data->{'end'}   + $offset;
  my $feature = Bio::EnsEMBL::SimpleFeature->new(
																 -start     => $feat_start,
																 -end       => $feat_end,
																 -strand    => $data->{'strand'},
																 -analysis  => $ana,
																 -score     => $data->{'score'},
																 -display_label => $data->{'label'},
																 -slice => $slice,
																);
  my $list = $feature_list{$self} ||= [];
  push @$list, $feature;
}

sub build_AssemblyTag {
  my ($self, $data) = @_;
}

sub build_AssemblyType {
  my ($self, $data) = @_;
  $sequence_set{$self}{'assembly_type'} = $data;

}

sub build_Exon {
  my ($self, $data) = @_;
  ##version ?? is_current
  my $slice = $self->get_ChromosomeSlice;
  my $exon = Bio::EnsEMBL::Exon->new(
												 -start     => $data->{'start'},
												 -end       => $data->{'end'},
												 -strand    => $data->{'strand'},
												 -stable_id => $data->{'stable_id'},
												 #-version   => 1,
												 -slice     => $slice,
												 -created_date => $time_now{$self},
												 -modified_date => $time_now{$self},
												);
  my $frame=$data->{'frame'};
  if (defined($frame)) {
	 $exon->phase((3-$frame)%3);
	 $exon->end_phase(($exon->length + $exon->phase)%3);
  } else {
	 $exon->phase(-1);
	 $exon->end_phase(-1);
  }
  my $list = $exon_list{$self} ||= [];
  push @$list, $exon;
}

sub build_Transcript {
  my ($self, $data) = @_;
  my $exons = delete $exon_list{$self};
  my $ana = $logic_ana{$self}{'Otter'} ||= Bio::EnsEMBL::Analysis->new(-logic_name => 'Otter');
  my $transcript = Bio::Vega::Transcript->new(
															 -stable_id => $data->{'stable_id'},
															 #-version   => 1,
															 -created_date=>$time_now{$self},
															 -modified_date=>$time_now{$self},
															 -analysis=>$ana,
															);
  ##translation start - end
  my $tran_start_pos=$data->{'translation_start'};
  my $tran_end_pos=$data->{'translation_end'};

  ##adding exon to transcript and finding translation position
  my ($start_Exon,$start_Exon_Pos,$end_Exon,$end_Exon_Pos);		
  foreach my $exon (@$exons) {
	 $transcript->add_Exon($exon);
	 if ( defined $tran_start_pos && !defined $start_Exon_Pos){
		$start_Exon_Pos=$self->translation_pos($tran_start_pos,$exon);
		$start_Exon=$exon;
	 }
	 if (defined $tran_end_pos && !defined $end_Exon_Pos){
		$end_Exon_Pos=$self->translation_pos($tran_end_pos,$exon);
		$end_Exon=$exon;
	 }
  }
  ##add translation to transcript
  if (defined $tran_start_pos && defined $tran_end_pos ){
	 if (!defined($start_Exon) || !defined($end_Exon)) {
		die "\n ERROR: Failed mapping translation to transcript with stable_id:".$data->{'stable_id'}.
		  "\n undefined start exon:$start_Exon or undefined end exon:$end_Exon\n";
	 }
	 else {
		my $translation = Bio::EnsEMBL::Translation->new(
																		 -stable_id=>$data->{'translation_stable_id'},
																		);
		$translation->start_Exon($start_Exon);
		$translation->start($start_Exon_Pos);
#		$translation->version(1);
		$translation->end_Exon($end_Exon);
		$translation->end($end_Exon_Pos);
		if ($start_Exon->strand == 1 && $start_Exon->start != $tran_start_pos) {
		  $start_Exon->end_phase(($start_Exon->length-$start_Exon_Pos+1)%3);
		} elsif ($start_Exon->strand == -1 && $start_Exon->end != $tran_start_pos) {
		  $start_Exon->end_phase(($start_Exon->length-$start_Exon_Pos+1)%3);
		}
		if ($end_Exon->length >= $end_Exon_Pos) {
		  $end_Exon->end_phase(-1);
		}
		$translation->created_date($time_now{$self});
		$translation->modified_date($time_now{$self});
		$transcript->translation($translation);
		##translation - version ???
	 }
  }
  elsif (defined $tran_start_pos || defined $tran_end_pos) {
	 die "ERROR: Only half of translation start/ end pair is defined\n";
  }

  ##biotype and status from transcript class name
  my ($biotype,$status);
  my $tr_class_name=$data->{'transcript_class'};
  $tr_class_name=lc($tr_class_name);
  my $mapref=$biotype_status_mapping{$self}->{$tr_class_name};		
  $biotype=$mapref->[0];
  $status=$mapref->[1];
  if ( defined $tr_class_name && !defined $biotype  ) {
	 $biotype=$data->{'transcript_class'};
	 $status = 'UNKNOWN';
  }
  if ( !defined $tr_class_name || !defined $biotype  ) {
	 die "transcript biotype and the status could not be mapped or found \n";
  }
  my $group='anything';
  my $author_name = $data->{'author'};
  my $author_email = $data->{'author_email'};
  my $author=$self->make_Author($author_name,$author_email,'');
  $transcript->transcript_author($author);
  $transcript->biotype($biotype);
  $transcript->status($status);

  ##transcript attributes
  my $transcript_attributes;
  my $mRNA_start_not_found = $data->{'mRNA_start_not_found'};
  if (defined $mRNA_start_not_found){
	 my $attrib=$self->make_Attribute('mRNA_start_NF','mRNA start not found','',$mRNA_start_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $mRNA_end_not_found = $data->{'mRNA_end_not_found'};
  if (defined $mRNA_end_not_found ){
	 my $attrib=$self->make_Attribute('mRNA_end_NF','mRNA end not found ','',$mRNA_end_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $cds_start_not_found = $data->{'cds_start_not_found'};
  if (defined $cds_start_not_found ){
	 my $attrib= $self->make_Attribute('cds_start_NF','cds start not not','',$cds_start_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $cds_end_not_found = $data->{'cds_end_not_found'};
  if (defined $cds_end_not_found ){
	 my $attrib= $self->make_Attribute('cds_end_NF','cds end not found','',$cds_end_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $remarks=$data->{'remark'};
  foreach my $rem (@$remarks){
	 my $attrib=$self->make_Attribute('remark','Remark','Annotation Remark',$rem);
	 push @$transcript_attributes,$attrib;
  }
  my $name=$data->{'name'};
  if (defined $name) {
	 if ($seen_transcript_name{$name}) {
		die "more than one transcript has the name $name";
	 } else {
		$seen_transcript_name{$name} = 1;
	 }
	 my $attrib=$self->make_Attribute('name','Name','Alternative/long name',$name);
	 push @$transcript_attributes,$attrib;
  }

  ##add transcript attributes
  $transcript->add_Attributes(@$transcript_attributes);

  ##evidence
  my $evidence=delete $evidence_list{$self};;
  if (defined $evidence) {
	 $transcript->add_Evidence($evidence);
  }
  my $list = $transcript_list{$self} ||= [];
  push @$list, $transcript;
}

sub translation_pos {
  my ($self,$loc,$exon) = @_;
  if ($loc <= $exon->end && $loc >= $exon->start) {
	 if ($exon->strand == 1) {
		return (($loc - $exon->start) + 1);
	 } else {
		return (($exon->end - $loc) + 1);
	 }
  }
  else {
	 return (undef);
  }
}

sub build_Locus {
  my ($self, $data) = @_;
  ## version and is_current ??
  my $transcripts = delete $transcript_list{$self};
  ## transcript author group has been temporarily set to 'anything' ??
  my $slice = $self->get_ChromosomeSlice;
  my $chrstart=$slice->start;
  my $ana = $logic_ana{$self}{'Otter'} ||= Bio::EnsEMBL::Analysis->new(-logic_name => 'Otter');
  my $gene = Bio::Vega::Gene->new(
											 -stable_id => $data->{'stable_id'},
											 -slice => $slice,
											 #-version => 1,
											 -created_date => $time_now{$self},
											 -modified_date => $time_now{$self},
											 -description => $data->{'description'},
											 -analysis => $ana,
											);


  ## biotype,source & status framed from gene type
  my ($biotype,$source,$status);
  my $gene_type=$data->{'type'};
  if (defined $gene_type) {
	 my $type;
	 if ($gene_type =~ /(\S+):(.+)/){
		##in future source will be a tag on itself indicating authority equivalent to group name
		$source = $1;
		$type=$2;
	 }
	 else {
		$type=$gene_type;
		$source = 'havana';
	 }
	 $type=lc($type);
	 my $mapref=$biotype_status_mapping{$self}->{$type};		
	 $biotype=$mapref->[0];
	 $status=$mapref->[1];
  }
  if (defined $gene_type && !defined $biotype  ) {
	 $biotype=$gene_type;
	 $status = 'UNKNOWN';
  }
  if (!defined $gene_type || !defined $biotype)   {
	 die "gene biotype, source and the status could not be mapped or found \n";
  }
  $gene->biotype($biotype);
  $gene->status($status);
  $gene->source($source);

  ##gene author
  my ($author,$author_name,$author_email);
  $author_name = $data->{'author'};
  $author_email = $data->{'author_email'};
  $author=$self->make_Author($author_name,$author_email,$source);
  $gene->gene_author($author);

  ##gene attributes name,synonym,remark
  my $gene_attributes=[];
  my $gene_name=$data->{'name'};
  if (defined $gene_name ) {
	 if ($seen_gene_name{$gene_name}) {
		die "more than one gene has the name $gene_name";
	 } else {
		$seen_gene_name{$gene_name} = 1;
	 }
	 my $name_attrib=$self->make_Attribute('name','Name','Alternative/long name',$gene_name);
	 push @$gene_attributes,$name_attrib;
  }
  my $gene_synonym=$data->{'synonym'};
  if (defined $gene_synonym){
	 foreach my $a (@$gene_synonym) {
		my $syn_attrib=$self->make_Attribute('synonym','Synonym','',$a);
		push @$gene_attributes,$syn_attrib;
	 }
  }
  my $gene_remark= $data->{'remark'};
  if (defined $gene_remark){
	 foreach my $rem (@$gene_remark){
		my $rem_attrib=$self->make_Attribute('remark','Remark','Annotation Remark',$rem);
		push @$gene_attributes,$rem_attrib;
	 }
  }
  ##share exons among transcripts of this gene
  $self->prune_exons($gene,$transcripts);
  ##add all gene attributes
  $gene->add_Attributes(@$gene_attributes);
  ##truncated flag
  my $truncated=$data->{'truncated'};
  if (defined $truncated) {
	 $gene->truncated_flag($truncated);
  }

  ##convert all exon coordinates from chromosomal coordinates to slice coordinates
  # not sure if this conversion is necessary ??
  #  if ($chrstart != 2000000000) {
  # foreach my $exon (@{$gene->get_all_Exons}) {
  #$exon->start($exon->start - $chrstart + 1);
  #$exon->end(  $exon->end   - $chrstart + 1);
  #}
  #}
  my $list = $gene_list{$self} ||= [];
  push @$list, $gene;
}

sub prune_exons {

  # keep track of all unique exons found so far to avoid making duplicates
  # share exons of a gene among all transcripts
  # need to be very careful about translation->start_exon and translation->end_Exon

  my ($self,$generef,$tref) = @_;
  my( %stable_key, %unique_exons );
  foreach my $tran (@$tref) {
	 my (@transcript_exons);
	 foreach my $exon (@{$tran->get_all_Exons}) {
		my $key = $self->exon_hash_key($exon);
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
	 if ($transcript_exons[0]->strand == 1) {
		@transcript_exons = sort {$a->start <=> $b->start} @transcript_exons;
	 } else {
		@transcript_exons = sort {$b->start <=> $a->start} @transcript_exons;
	 }
	 foreach my $exon (@transcript_exons) {
		$tran->add_Exon($exon);
	 }
	 $generef->add_Transcript($tran);
  }
}

sub exon_hash_key {
  my( $self,$exon ) = @_;
  # This assumes that all the exons we
  # compare will be on the same contig
  return join(" ",
				  $exon->start,
				  $exon->end,
				  $exon->strand,
				  $exon->phase,
				  $exon->end_phase);
}

sub report_set_end {
  my ($self) = @_;
  # Do nothing
}

###load parsed otter objects to otter database

sub LoadAssemblySlices {

##add more command-line sequence-set arguments like description,replace
##this would make the current sequence-set as the latest and hide=Y for the
##current sequence-set and the sequence set specified in the replace option
##update chromosome length

  my ($self,$db)= @_;
  eval {
	 $db->begin_work();
	 my $dbc= $db->dbc();
	 my $sa=$db->get_SliceAdaptor();
	 my $slice=$self->get_AssemblySlices;
	 my $chr_slice=$slice->{'chr'};
	 my $new_slice=$self->get_SliceId($chr_slice,$db);
	 my $asm_seq_reg_id=$sa->get_seq_region_id($new_slice);
	 my $chr_ctg = $slice->{'chr_ctg'};
	 ##insert all contigs
	 foreach my $piece (@$chr_ctg) {
		my $asm_slice = $piece->[0];
		my $cmp_slice = $piece->[1];
		my $new_slice=$self->get_SliceId($cmp_slice,$db);
		my $cmp_seq_reg_id=$sa->get_seq_region_id($new_slice);
		##insert chromosome-contig assembly
		$self->insert_Assembly($dbc,$asm_seq_reg_id,$cmp_seq_reg_id,$asm_slice->start,$asm_slice->end,$cmp_slice->start,$cmp_slice->end,$cmp_slice->strand);
		
		##insert contig_info and attributes
		my $ctg_attrib_list=$piece->[2];
		my $ctg_author=$piece->[3];
		my $ctg_info_id = $self->insert_ContigInfo_Attributes($db,$ctg_author,$new_slice,$ctg_attrib_list);
		
	 }
	 my $cln_ctg = $slice->{'cln_ctg'};
	 ##insert all clones
	 foreach my $piece (@$cln_ctg) {
		my $asm_slice = $piece->[0];
		my $cmp_slice = $piece->[1];
		my $new_slice=$self->get_SliceId($asm_slice,$db);
		my $asm_seq_reg_id=$sa->get_seq_region_id($new_slice);
		$new_slice=$self->get_SliceId($cmp_slice,$db);
		my $cmp_seq_reg_id=$sa->get_seq_region_id($new_slice);
		##insert clone-contig assembly
		$self->insert_Assembly($dbc,$asm_seq_reg_id,$cmp_seq_reg_id,$asm_slice->start,$asm_slice->end,$cmp_slice->start,$cmp_slice->end,$cmp_slice->strand);
	 }
  };
  if ($@) {
	 $db->rollback;
	 print STDERR "Error saving genes from file:".$@;
  }
  else {
	 $db->commit;
  }
}

sub insert_ContigInfo_Attributes {
  my ($self,$db,$ctg_author,$ctg_slice,$ctg_attrib_list)=@_;
  my $dbc= $db->dbc();
  my $ca=$db->get_ContigInfoAdaptor();
  my $contig_info=$self->make_ContigInfo($ctg_slice,$ctg_author,$ctg_attrib_list);
  $ca->store($contig_info);
}

sub  insert_Assembly {
  my($self,$dbc,$asm_seq_reg_id,$cmp_seq_reg_id,$asm_start,$asm_end,$cmp_start,$cmp_end,$cmp_strand) = @_;
  my $select_assembly=$dbc->prepare("select count(*) from assembly where asm_seq_region_id = ? and cmp_seq_region_id = ? and asm_start =? and asm_end = ? and cmp_start = ? and cmp_end = ? and ori = ?");
  $select_assembly->execute($asm_seq_reg_id,$cmp_seq_reg_id,$asm_start,$asm_end,$cmp_start,$cmp_end,$cmp_strand);
  my ($count) = $select_assembly->fetchrow;
  if ($count > 0) {
	 print STDERR "assembly already in table with asm_seq_reg_id :$asm_seq_reg_id, and so not loaded\n";
  }
  else {
	 my  $insert_assembly=$dbc->prepare("insert into assembly
	  (asm_seq_region_id ,cmp_seq_region_id ,asm_start ,asm_end ,cmp_start ,cmp_end ,ori)
	  values  (?, ?,?,?,?,?,?)");
	 $insert_assembly->execute($asm_seq_reg_id,$cmp_seq_reg_id,$asm_start,$asm_end
										,$cmp_start,$cmp_end,$cmp_strand);
  }
}

##get instant variable values of instantiated object

sub get_SliceId {
  my ($self,$slice,$db)=@_;
  my $dbc= $db->dbc();
  my $sa=$db->get_SliceAdaptor();
  my $csa = $db->get_CoordSystemAdaptor();
  my ($seq_reg_id,$new_slice,$slice_cs,$cs);
  ## check if the contig is already stored in db
  $slice_cs=$slice->coord_system;
  eval{
	 $cs = $csa->fetch_by_name($slice_cs->name,$slice_cs->version,$slice_cs->rank);
  };
  if($@){
	 print STDERR "A coord_system matching the arguments does not exsist in the cord_system table, please ensure you have the right coord_system entry in the database:$@";
  }
  $new_slice = $sa->fetch_by_name($slice->name);
  if($new_slice){
	 warn "slice <".$slice->seq_region_name."> is already in the database\n";
	 $seq_reg_id = $sa->get_seq_region_id($new_slice);
  }
  else {
	 ##make a new slice with the coord_system of the database for contig
	 $new_slice=$self->make_Slice($slice->seq_region_name,1,$slice->end,$slice->end,1,$cs);
	 my $seq;
	 my $seq_name=$slice->seq_region_name;
	 if ($slice_cs->name eq 'contig') {
		##fetch sequence for contig
		my ($acc_ver)=$seq_name =~ /^(.+\.\d+)\.\d+\.\d+$/;
		my $seqobj = $self->pfetch_acc_ver($acc_ver);
		$seq   = $seqobj->seq;
		##insert slice
		$seq_reg_id = $sa->store($new_slice,\$seq);
		##assign new slice
		$slice=$new_slice;
	 }
	 else {
		##insert slice
		$seq_reg_id = $sa->store($new_slice);
		##assign new slice
		$slice=$new_slice;
		if ($slice_cs->name eq 'clone') {
		  ##make clone attributes
		  my @attrib;
		  my $aa = $db->get_AttributeAdaptor();
		  my ($acc,$sv)= $seq_name=~/^(.+)\.(\d+)$/;
		  push @attrib,$self->make_Attribute('htgs_phase','HTGS Phase','High Throughput Genome Sequencing Phase','3');
		  push @attrib,$self->make_Attribute('intl_clone_name','International Clone Name','',$seq_name);
		  push @attrib,$self->make_Attribute('embl_accession','EMBL Accession','',$acc);
		  push @attrib,$self->make_Attribute('embl_version','EMBL Version','',$sv);
		  ##store clone attributes
		  $aa->store_on_Slice($new_slice,\@attrib);
		}
		if ($slice_cs->name eq 'chromosome') {
		  ##make chromosome attributes
		  my $attrib=$slice{$self}{'chr_attrib'};
		  if (defined $attrib){
			 my $aa = $db->get_AttributeAdaptor();
			 $aa->store_on_Slice($new_slice,$attrib);
		  }
		}
	 }
  }
  return $new_slice;
}

sub get_AssemblyType {
  my $self=shift;
  return $sequence_set{$self};
}

sub get_ChromosomeSlice {
  my $self=shift;
  return $slice{$self}{'chr'};
}

sub get_AssemblySlices {
  my $self=shift;
  return $slice{$self};
}

sub get_Genes {
  my $self=shift;
  return $gene_list{$self};
}

###fetch sequence

sub pfetch_acc_ver {
  my( $self,$acc_ver ) = @_;
  my $pfetch         ||= Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new;
  my $pfetch_archive ||= Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new(
																											 -PFETCH_PORT => 23100,);
  my $seq = $pfetch->get_Seq_by_acc($acc_ver);
  unless ($seq) {
	 warn "Fetching '$acc_ver' from archive\n";
	 $seq = $pfetch_archive->get_Seq_by_acc($acc_ver);
  }
  unless ($seq) {
	 die "cannot fetch sequence\n";
  }
  return $seq;
}

##make Otter objects methods

sub make_Attribute{
  my ($self,$code,$name,$description,$value) = @_;
  my $attrib = Bio::EnsEMBL::Attribute->new
	 (
	  -CODE => $code,
	  -NAME => $name,
	  -DESCRIPTION => $description,
	  -VALUE => $value
	 );
  return $attrib;
}

sub make_ContigInfo{
  my ($self,$ctg_slice,$author,$attributes) = @_;
  my $ctg_info = Bio::Vega::ContigInfo->new
	 (
	  -slice => $ctg_slice,
	  -author => $author,
	  -attributes => $attributes
	 );
  return $ctg_info;
}

sub make_CoordSystem {
  my ($self,$name) = @_;
  if (!defined $name) {
	 die "coord system name is a must to create a coordinate system object\n";
  }
  unless ($coord_system{$self}{$name}){
	 my $rank;
	 my $default=1;
	 my $seq_level=0;
	 my $version;
	 if ($name eq 'chromosome') {
		$version=$self->init_CoordSystem_Version;
		if ($version eq 'otter'){
		  $rank=2;
		  $default=0;
		}
		elsif ($version eq 'vega'){
		  $rank=1;
		}
	 }
	 if ($name eq 'contig'){
		$seq_level=1;
		$rank=5;
	 }
	 elsif ($name eq 'clone'){
		$rank=4;
	 }
	 elsif ($name eq 'supercontig'){
		$rank=3;
	 }
	 $coord_system{$self}{$name} =  Bio::EnsEMBL::CoordSystem->new(
																						-name    => $name,
																						-version => $version,
																						-rank    => $rank,
																						-default => $default,
																						-sequence_level => $seq_level
																					  );
  }
  return $coord_system{$self}{$name};
}

sub make_Slice {
  my ($self,$seq_region_name,$start,$end,$length,$strand,$coord_system)=@_;
  my $slice = Bio::EnsEMBL::Slice->new
	 (
	  -seq_region_name   => $seq_region_name,
	  -start             => $start,
	  -end               => $end,
	  -seq_region_length => $length,
	  -strand            => $strand,
	  -coord_system      => $coord_system,
	 );
  return $slice;
}

sub make_Author {
  my ($self,$name,$email,$group_name)=@_;
  my $group = Bio::Vega::AuthorGroup->new
	 (
	  -name   => $group_name,
	 );
  my $author = Bio::Vega::Author->new
	 (
	  -name   => $name,
	  -email  => $email,
	  -group  => $group,
	 );
  return $author;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::Otter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

