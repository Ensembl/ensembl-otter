package Bio::Vega::DBSQL::GeneAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::Vega::Gene;
use Bio::Vega::Transcript;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);
use Data::Dumper;

use base 'Bio::EnsEMBL::DBSQL::GeneAdaptor';

sub fetch_by_stable_id  {
  my ($self, $stable_id) = @_;
  my ($gene) = $self->SUPER::fetch_by_stable_id($stable_id);
  if ($gene){
	 $self->reincarnate_gene($gene);
  }
  return $gene;
}

sub reincarnate_gene {
  my ($self,$gene)=@_;
  bless $gene, "Bio::Vega::Gene";
  $self->fetch_gene_author($gene);
  my $transcripts=$gene->get_all_Transcripts;
  foreach my $tr (@$transcripts){
	 bless $tr, "Bio::Vega::Transcript";
	 my $ta=$self->db->get_TranscriptAdaptor;
	 $ta->fetch_transcript_author($tr);
  }
  return $gene;
}

sub fetch_all_by_Slice  {
  my ($self,$slice,$logic_name,$load_transcripts)  = @_;
  my $latest_genes = [];
  my ($genes) = $self->SUPER::fetch_all_by_Slice($slice,$logic_name,$load_transcripts);
  if ($genes){
	 foreach my $gene(@$genes){
		$self->reincarnate_gene($gene);
		my $tsct_list = $gene->get_all_Transcripts;
		for (my $i = 0; $i < @$tsct_list;) {
		  my $transcript = $tsct_list->[$i];
		  my( $t_name );
		  eval{
			 my $t_name_att = $transcript->get_all_Attributes('name') ;
			 if ($t_name_att->[0]){
				$t_name=$t_name_att->[0]->value;
			 }
		  };
		  if ($@) {
			 die sprintf("Error getting name of %s %s (%d):\n$@", 
							 ref($transcript), $transcript->stable_id, $transcript->dbID);
		  }
		  my $exons_truncated = $transcript->truncate_to_Slice($slice);
		  my $ex_list = $transcript->get_all_Exons;
		  my $message;
		  my $truncated=0;
		  if (@$ex_list) {
			 $i++;
			 if ($exons_truncated) {
				$message ="Transcript '$t_name' has $exons_truncated exon";
				if ($exons_truncated > 1) {
				  $message .= 's that are not in this slice';
				} else {
				  $message .= ' that is not in this slice';
				}
				$truncated=1;
				
			 }
		  }
		  else {
			 # This will fail if get_all_Transcripts() ceases to return a ref
			 # to the actual list of Transcripts inside the Gene object
			 splice(@$tsct_list, $i, 1);
			 $message="Transcript '$t_name' has no exons within the slice";
			 $truncated=1;
		  }
		  if ($truncated == 1) {
			 my $remark_att = Bio::EnsEMBL::Attribute->new(-CODE => 'remark',-NAME => 'Remark',-DESCRIPTION => 'Annotation Remark',-VALUE => $message);
			 my $gene_att=$gene->get_all_Attributes;
			 push @$gene_att, $remark_att ;
			 $gene->truncated_flag(1);
			 print STDERR "Found a truncated gene";
		  }
		}
		# Remove any genes that don't have transcripts left.
		if (@$tsct_list) {
		  push(@$latest_genes, $gene);
		}
	 }
  }
  return $latest_genes;
}

sub get_deleted_Gene_by_slice{
  my ($self, $gene,$gene_version) = @_;
  unless ($gene || $gene_version){
	 throw("no gene passed on to fetch old gene or no version supplied");
  }
  my $gene_slice=$gene->slice;
  my $gene_stable_id=$gene->stable_id;
  my $db_gene;
  my @out = grep { $_->stable_id eq $gene_stable_id and $_->version eq $gene_version }
    @{$self->SUPER::fetch_all_by_Slice_constraint($gene_slice,'g.is_current = 0 ')};
  if ($#out > 1) {
	 ##test
	 @out = sort {$a->dbID <=> $b->dbID} @out;
	 $db_gene=pop @out;
	 ##test
  }
  else {
	 $db_gene=$out[0];
  }
  if ($db_gene){
	 $self->reincarnate_gene($db_gene);
  }
  return $db_gene;
}

sub fetch_by_stable_id_version  {
  my ($self, $stable_id,$version) = @_;
  unless ($stable_id || $version) {
	 throw("Must enter a gene stable id:$stable_id and version:$version to fetch a Gene");
  }
  my $constraint = "gsi.stable_id = '$stable_id' AND gsi.version = '$version'";
  my ($gene) = @{ $self->generic_fetch($constraint) };
  $self->reincarnate_gene($gene);
  return $gene;
}

sub fetch_gene_author {
  my ($self,$gene)=@_;
  my $authad = $self->db->get_AuthorAdaptor;
  my $author= $authad->fetch_gene_author($gene->dbID);
  $gene->gene_author($author);
  return $gene;
}


sub check_for_change_in_gene_components {
  ## check if any of the gene component (transcript,exons,translation) has changed
  my ($self,$sida,$gene) = @_;
  my $transcripts=$gene->get_all_Transcripts;
  my $ta=$self->db->get_TranscriptAdaptor;
  my $tran_change_count=0;
  my $shared_exons_bet_txs;
  foreach my $tran (@$transcripts) {
	 ##assign stable_id for new trancript
	 unless ($tran->stable_id) {
		$tran->stable_id($sida->fetch_new_transcript_stable_id);
	 }
	 ##check if exons are new or old and if old whether they have changed or not
	 my $exons=$tran->get_all_Exons;
	 my $exon_changed=0;
	 ($exon_changed,$shared_exons_bet_txs)=$self->exons_diff($sida,$exons,$shared_exons_bet_txs);
	 ##check if translation has changed
#	 my $db_transcript=$ta->get_current_Transcript_by_slice($tran);
	 ##note:with assembly
	 my $db_transcript=$ta->fetch_by_stable_id($tran->stable_id);
	 my $translation_changed=0;
	 $translation_changed=$self->translation_diff($sida,$tran,$db_transcript);

	 ##check if transcript is new or old
	 ##if transcript is old compare to see if transcript has changed
	 my $transcript_changed=0;

	 $tran->is_current(1);
	 if ( $db_transcript){
		
		$transcript_changed=compare($db_transcript,$tran);
		my $db_version=$db_transcript->version;
		if ($exon_changed==1 || $translation_changed==1 ) {
		  $transcript_changed = 1;
		}
		$db_transcript->is_current(0);
		$ta->update($db_transcript);

		##if transcript has changed then increment version
		if ($transcript_changed==1 ) {
		  $tran->version($db_version+1);
		  ##add for transcript synonym
		  $self->add_synonym($db_transcript,$tran);
		}
		##if transcript has not changed then retain the same old version
		else {
		  $tran->version($db_version);
		  ##retain old author
		  $tran->transcript_author($db_transcript->transcript_author);
		}	
	 }
	 ##if transcript is new
	 else {
		my $restored_transcripts=$ta->fetch_all_versions_by_stable_id($tran->stable_id);
		if (@$restored_transcripts == 0){
		  $tran->version(1);
		}
		##restored transcript
		else {
		  my $old_version=1;
		  foreach my $t (@$restored_transcripts){
			 if ($t->version > $old_version){
				$old_version=$t->version;
			 }
		  }
		  $tran->version($old_version);
		  ##check to see if the restored transcript has changed
#		  my $old_transcript=$ta->get_deleted_Transcript_by_slice($tran,$old_version);
		  ##note:with assembly
		  my $old_transcript=$ta->fetch_by_stable_id_version($tran->stable_id,$old_version);
		  my $old_translation=$old_transcript->translation;
		  $translation_changed=$self->translation_diff($sida,$tran,$old_transcript);
		  $transcript_changed=compare($old_transcript,$tran);
		  if ($exon_changed == 1 || $translation_changed == 1) {
			 $transcript_changed = 1;
		  }
		  if ($transcript_changed == 1){
			 $tran->version($old_version+1);
			 ##add for transcript synonym
			 $self->add_synonym($old_transcript,$tran);
		  }
		}
	 }
	 if ($transcript_changed == 1) {
		$tran_change_count++;
	 }
	 ##check to see if the start_Exon,end_Exon has been assigned right after comparisons
	 my $translation = $tran->translation();
	 if( defined $translation ) {
		#make sure that the start and end exon are set correctly
		my $start_exon = $translation->start_Exon();
		my $end_exon   = $translation->end_Exon();
		if(!$start_exon) {
		  throw("Translation does not define a start exon.");
		}
		if(!$end_exon) {
		  throw("Translation does not define an end exon.");
		}
		if(!$start_exon->dbID()) {
		  my $key = $start_exon->hashkey();
		  ($start_exon) = grep {$_->hashkey() eq $key} @$exons;
		  if($start_exon) {
			 $translation->start_Exon($start_exon);
		  } else {
			 ($start_exon) = grep {$_->stable_id eq $start_exon->stable_id} @$exons;
			 if($start_exon) {
				$translation->start_Exon($start_exon);
			 }
			 else {
				throw("Translation's start_Exon does not appear to be one of the " .
						"exons in its associated Transcript");
			 }
		  }
		}
		if(!$end_exon->dbID()) {
		  my $key = $end_exon->hashkey();
		  ($end_exon) = grep {$_->hashkey() eq $key} @$exons;
		  if($end_exon) {
			 $translation->end_Exon($end_exon);
		  } else {
			 ($end_exon) = grep {$_->stable_id eq $end_exon->stable_id} @$exons;
			 if($end_exon) {
				$translation->end_Exon($end_exon);
			 }
			 else {
				throw("Translation's end_Exon does not appear to be one of the " .
						"exons in its associated Transcript.");
			 }
		  }
		}
	 }
  }
  my $transcripts_changed=0;
  if ($tran_change_count > 0) {
	 $transcripts_changed=1;
  }
  return $transcripts_changed;
}


sub update_deleted_transcripts {
  my ($self,$new_trs,$old_trs)=@_;
  my %newhash = map { $_->stable_id => $_} @$new_trs;
  my %oldhash = map { $_->stable_id => $_} @$old_trs;
  my $ta=$self->db->get_TranscriptAdaptor;
  while (my ($key, $old_t) = each %oldhash) {
    unless ($newhash{$key}) {
		$old_t->is_current(0);
		$ta->update($old_t);
    }
  }

}

sub update_deleted_exons {
  my ($self,$new_exons,$old_exons)=@_;
  my %newhash = map { $_->stable_id => $_} @$new_exons;
  my %oldhash = map { $_->stable_id => $_} @$old_exons;
  my $ea=$self->db->get_ExonAdaptor;
  while (my ($key, $old_e) = each %oldhash) {
    unless ($newhash{$key}) {
		$old_e->is_current(0);
		$ea->update($old_e);
    }
  }

}

sub translation_diff{
  my ($self,$sida,$tran,$db_transcript)=@_;
  my $translation_changed=0;
  my $translation;
  my $db_translation;
  if (defined $tran){
	 $translation=$tran->translation;
  }
  if (defined $db_transcript) {
	 $db_translation=$db_transcript->translation;
  }
  if (defined $translation) {
	 unless ($translation->stable_id) {
		$translation->stable_id($sida->fetch_new_translation_stable_id);
		$translation->version(1);
	 }
  }
  if (! defined $db_translation && defined $translation){
	 $translation->version(1);
	 $translation_changed=1;
	 return 1;
  }
  if (! defined $translation && defined $db_translation){
	 $translation_changed=1;
	 return 1;
  }
  if (defined $db_translation && defined $translation){
	 my $db_version=$db_translation->version;

	 if ($db_translation->stable_id ne $translation->stable_id) {
		#Remember to uncomment this after loading and remove the line/s after
		#	throw('translation stable_ids of the same two transcripts are different\n');
		my $translation_adaptor=$self->db->get_TranslationAdaptor;
		my $not_good_and_new_translation=$translation_adaptor->fetch_by_stable_id($translation->stable_id);
		if (defined $not_good_and_new_translation){
		  throw ("new translation stable_id for this transcript is already associated with someother gene's transcript");
		}
		$translation_changed=1;
		$db_version=0;
	 }
	 else {
		$translation_changed=compare($db_translation,$translation);
	 }


	 if ($translation_changed==1){
		$translation->version($db_version+1);
	 }
	 else {
		$translation->version($db_version);
	 }
  }
  if (!defined $translation && !defined $db_translation){
	 $translation_changed=0;
	 return $translation_changed;
  }
  return $translation_changed;
}


sub exons_diff {
  my ($self,$sida,$exons,$shared)=@_;
  my $exon_changed=0;
  my $ea=$self->db->get_ExonAdaptor;
  ##check if exon is new or old
  foreach my $exon (@$exons){
	 ##assign stable_id for new exon
	 unless ($exon->stable_id) {
		$exon->stable_id($sida->fetch_new_exon_stable_id);
	 }
#	 my $db_exon=$ea->get_current_Exon_by_slice($exon);
	 ##note:with assembly
	 my $db_exon=$ea->fetch_by_stable_id($exon->stable_id);
	 if ( $db_exon){
		my $db_version=$db_exon->version;
      $exon_changed=compare($db_exon,$exon);
		##if exon has changed then increment version
		if ($exon_changed == 1){
		  $db_exon->is_current(0);
		  $ea->update($db_exon);
		  $exon->version($db_version+1);
		  $exon->is_current(1);
		}
		##if exon has not changed then use the same old db exon, saves db space by not creating exons with same version
		else {
		  $exon=$db_exon;
		}
	 }
	 ##if exon is new
	 else {
		my $restored_exons=$ea->fetch_all_versions_by_stable_id($exon->stable_id);
		if (@$restored_exons == 0){
		  $exon->version(1);
		  $exon->is_current(1);
		}
		##restored exon or a currently shared exon of the transcripts of the same gene 
		##which has changed and hence deleted by a previous transcript
		else {
		  ##shared exon
		  if (exists $shared->{$exon->stable_id}){
			 $exon=$shared->{$exon->stable_id};
		  }
		  ##restored exon
		  else {
			 my $old_version=1;
			 foreach my $e (@$restored_exons){
				if ($e->version > $old_version){
				  $old_version=$e->version;
				}
			 }
			 $exon->version($old_version);
			 $exon->is_current(1);
			 ##check to see if the restored exon has changed
			 #my $old_exon=$ea->get_deleted_Exon_by_slice($exon,$old_version);
			 ##note:with assembly
			 my $old_exon=$ea->fetch_by_stable_id_version($exon->stable_id,$old_version);
			 $exon_changed=compare($old_exon,$exon);
			 if ($exon_changed == 1){
				$exon->version($old_version+1);
			 }
		  }
		}
	 }
	 ##create a distinct list of all exons of all transcripts of the gene
	 if (! exists $shared->{$exon->stable_id}){
		$shared->{$exon->stable_id}=$exon;
	 }
  }
  return ($exon_changed,$shared);
}

sub get_current_Gene_by_slice{
  my ($self, $gene) = @_;
  unless ($gene){
	 throw("no gene passed on to fetch old gene");
  }
  my $gene_slice=$gene->slice;
  my $gene_stable_id=$gene->stable_id;
  my @out = grep { $_->stable_id eq $gene_stable_id }
    @{ $self->fetch_all_by_Slice_constraint($gene_slice,'g.is_current = 1 ')};
  if ($#out > 1) {
	 die "there are more than one gene retrived\n";
  }
  my $db_gene=$out[0];
  if ($db_gene){
	 $self->reincarnate_gene($db_gene);
  }
  return $db_gene;
}

sub delete_gene {
  my ($self,$del_gene)=@_;
  ##update deleted genes
  my $tref=$del_gene->get_all_Transcripts();
  my $tran_adaptor=$self->db->get_TranscriptAdaptor;
  my $exon_adaptor=$self->db->get_ExonAdaptor;
  foreach my $del_tran (@$tref) {
	 $del_tran->is_current(0);
	 $tran_adaptor->update($del_tran);
	 foreach my $del_exon (@{$del_tran->get_all_Exons}) {
		$del_exon->is_current(0);
		$exon_adaptor->update($del_exon);
	 }
  }
  $del_gene->is_current(0);
  $self->update($del_gene);


}

sub force_load {
  my ($self,$gene)=@_;
  ##get db gene ,if one and delete it
  my $db_gene=$self->fetch_by_stable_id($gene->stable_id);
  if ($db_gene){
	 $self->delete_gene($db_gene);
  }
  $self->SUPER::store($gene);	
  my $aa = $self->db->get_AuthorAdaptor;
  my $gene_author=$gene->gene_author;
  $aa->store($gene_author);
  my $author_id=$gene_author->dbID;
  $aa->store_gene_author($gene->dbID,$author_id);
  ##transcript-author, transcript-evidence
  my $transcripts=$gene->get_all_Transcripts;
  my $ta = $self->db->get_TranscriptAdaptor;
  foreach my $tran (@$transcripts){
	 ##author
	 my $tran_author=$tran->transcript_author;
	 $aa->store($tran_author);
	 my $author_id=$tran_author->dbID;
	 $aa->store_transcript_author($tran->dbID,$author_id);
	 ##evidence
	 my $evidence_list=$tran->get_Evidence;
	 $ta->store_Evidence($tran->dbID,$evidence_list);
  }
}


=head2 store

 Title   : store
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub store{
  my ($self,$gene,$forceload) = @_;

  unless ($gene) {
	 throw("Must enter a Gene object to the store method");
  }
  unless ($gene->isa("Bio::Vega::Gene")) {
	 throw("Object must be a Bio::Vega::Gene object. Currently [$gene]");
  }
  unless ($gene->gene_author) {
	 throw("Bio::Vega::Gene must have a gene_author object set");
  }
  ##checks for the gene object so that the gene object has all the right adaptors
  ##like the slice adaptor, coord-system adaptor and its attribs are properly set for
  ##storing it in the db
  my $sa = $self->db->get_SliceAdaptor();
  my $slice = $gene->slice;
  unless ($slice) {
	 throw "gene does not have a slice attached to it, cannot store gene\n";
  }
  my $csa = $self->db->get_CoordSystemAdaptor();
  my $slice_cs = $slice->coord_system;
  unless ($slice_cs) {
	 throw("Coord System not set in gene slice \n");
  }
  my $coord_system_id=$slice->coord_system->dbID();

##
##cut
##

#COMMENT

  unless ( $coord_system_id){
	 my $db_cs;
	 eval{
		$db_cs = $csa->fetch_by_name($slice_cs->name,$slice_cs->version,$slice_cs->rank);
	 };
	 if($@){
		print STDERR "A coord_system matching the arguments does not exist in the coord_system".
		  "table, please ensure you have the right coord_system entry in the database:$@";
	 }
	 my $new_slice = $sa->fetch_by_name($slice->name);
	 unless($new_slice){
		throw "gene slice is not in the database\n";
	 }
	 $gene->slice($new_slice);
	 my $tref=$gene->get_all_Transcripts();
	 foreach my $tran (@$tref) {
		$tran->slice($new_slice);
		foreach my $exon (@{$tran->get_all_Exons}) {
		  $exon->slice($new_slice);
		}
	 }
  }

#cut

##
##cut
##
  unless ($gene->slice->adaptor){
	 $gene->slice->adaptor($sa);
  }

  if ($forceload) {
	 $self->force_load($gene);
  }

  unless ($forceload) {

  my $gene_changed=0;

  if ($self->db->check_for_transaction != 0){
	 throw "This is non-transactional , cannot proceed storing of gene\n";
  }

  $self->db->savepoint;


  ##deleted gene
  my $db_gene;
  if ($gene->is_current == 0) {
	 $self->delete_gene($gene);
	 $gene_changed = 5;
  }
  else {
	 ##new gene - assign stable_id
	 my $sida = $self->db->get_StableIdAdaptor();
	 unless ($gene->stable_id){
		$sida->fetch_new_stable_ids_for_Gene($gene);
	 }
	 ##if gene is old compare to see if gene components have changed
	 ##check if gene is new or old
	 my $gene_slice=$gene->slice;
#	 $db_gene=$self->get_current_Gene_by_slice($gene);
	 ##note:with assembly
	 $db_gene=$self->fetch_by_stable_id($gene->stable_id);
	 if ( $db_gene && $gene_changed != 5) {
		$gene_changed=$self->check_for_change_in_gene_components($sida,$gene);
		my $db_version=$db_gene->version;
		if ($gene_changed == 0) {
		  $gene_changed=compare($db_gene,$gene);
		}
		$gene->is_current(1);
		$db_gene->is_current(0);
		$self->update($db_gene);
		if ( $gene_changed == 1) {
		  $gene->version($db_version+1);
		  ##add synonym if old gene name is not a current gene synonym
		  $self->add_synonym($db_gene,$gene);
		}
		else {
		  $gene->version($db_version);
		}
	 }
	 
	 ##if gene is new /restored
	 if (! $db_gene && $gene_changed != 5) {
		my $restored_genes = $self->fetch_all_versions_by_stable_id($gene->stable_id);
		##restored gene
		if (@$restored_genes > 0){
		  my $old_version=1;
		  foreach my $g (@$restored_genes){
			 if ($g->version > $old_version){
				$old_version=$g->version;
			 }
		  }
		  ##check to see change in components
		  $gene->version($old_version);
		  $gene->is_current(1);
		  $gene_changed=$self->check_for_change_in_gene_components($sida,$gene);
		  if ($gene_changed == 1)  {
			 $gene->version($old_version+1);
		  }
		  else {
			 ##compare this gene with the highest version of the old genes
			 ##if gene changed
			 #my $old_gene=$self->get_deleted_Gene_by_slice($gene,$old_version);
			 ##note:with assembly
			 my $old_gene=$self->fetch_by_stable_id_version($gene->stable_id,$old_version);
			 $gene_changed=compare($old_gene,$gene);
			 if ($gene_changed == 1){
				$gene->version($old_version+1);
				##add synonym if old gene name is not a current gene synonym
				$self->add_synonym($old_gene,$gene);
			 }
			 else {
				$gene_changed=3;
			 }
		  }
		}
		##new gene
		else {
		  $gene->version(1);
		  $gene->is_current(1);
		  ##check if any of the gene components are old and if so have changed
		  ($gene_changed)=$self->check_for_change_in_gene_components($sida,$gene);
		  $gene_changed=2;
		  ##store gene and its components
		  $self->SUPER::store($gene);
		}
	 }
  }
  if ($gene_changed == 1 || $gene_changed == 3 || $gene_changed == 5) {
	 if ($gene_changed == 5){
		$gene->dbID(undef);
		$gene->adaptor(undef);
		my $tref=$gene->get_all_Transcripts();
		foreach my $tran (@$tref) {
		  $tran->dbID(undef);
		  $tran->adaptor(undef);
		  if ($tran->translation){
			 $tran->translation->dbID(undef);
			 $tran->translation->adaptor(undef);
		  }
		}
	 }
	 $self->SUPER::store($gene);
  }
  if ($gene_changed==1 || $gene_changed==2 || $gene_changed == 3 || $gene_changed == 5){
	 ##get author_id and store gene_id-author_id in gene_author table
	 my $aa = $self->db->get_AuthorAdaptor;
	 my $gene_author=$gene->gene_author;
	 $aa->store($gene_author);
	 my $author_id=$gene_author->dbID;
	 $aa->store_gene_author($gene->dbID,$author_id);
	 ##transcript-author, transcript-evidence
	 my $transcripts=$gene->get_all_Transcripts;
	 my $ta = $self->db->get_TranscriptAdaptor;
	 foreach my $tran (@$transcripts){
		##author
		my $tran_author=$tran->transcript_author;
		$aa->store($tran_author);
		my $author_id=$tran_author->dbID;
		$aa->store_transcript_author($tran->dbID,$author_id);
		##evidence
		my $evidence_list=$tran->get_Evidence;
		$ta->store_Evidence($tran->dbID,$evidence_list);
	 }
  }
  if ($gene_changed == 1) {
	 if ($db_gene){
		my $new_trs=$gene->get_all_Transcripts;
		my $old_trs;
		my $new_tr_count=@$new_trs;
		my $old_tr_count;
		$old_trs=$db_gene->get_all_Transcripts;
		$old_tr_count=@$old_trs;
		if ($old_tr_count > $new_tr_count) {
		  $self->update_deleted_transcripts($new_trs,$old_trs);
		}
		my $new_exons=$gene->get_all_Exons;
		my $old_exons;
		my $new_exon_count=@$new_exons;
		my $old_exon_count;
		$old_exons=$db_gene->get_all_Exons;
		$old_exon_count=@$old_exons;
		if ($old_exon_count > $new_exon_count) {
		  $self->update_deleted_exons($new_exons,$old_exons);
		}
	 }
	 #print STDERR "\nChanged gene:".$gene->stable_id." Current Version:".$gene->version." changes stored successfully in db\n";
  }
  if ($gene_changed == 0) {
	 $self->db->rollback_to_savepoint;
#	 print STDERR "\nTrying to store an Unchanged gene:".$gene->stable_id." Version:".$gene->version." nothing written in db\n";
  }
  if ($gene_changed == 2) {
	# print STDERR "\nNew gene:".$gene->stable_id." Version:".$gene->version." stored successfully in db\n";
  }
  if ($gene_changed == 3) {
	 #print STDERR "\nRestored gene:".$gene->stable_id." Version:".$gene->version." restored successfully in db\n";
  }
  if ($gene_changed == 5) {
	 #print STDERR "\nDeleted gene:".$gene->stable_id." Version:".$gene->version." deleted successfully in db\n";
  }
}
}


sub add_synonym{

  my ($self,$db_obj,$obj)=@_;
  my $db_obj_name=$db_obj->get_all_Attributes('name');
  my $db_n;
  if ($db_obj_name) {
	 if (defined $db_obj_name->[0]){
		$db_n=$db_obj_name->[0]->value;
	 }
  }
  my $obj_name=$obj->get_all_Attributes('name');
  my $n;
  if ($obj_name) {
	 if (defined $obj_name->[0]){
		$n=$obj_name->[0]->value;
	 }
  }
  my $synonyms = $obj->get_all_Attributes('synonym');
  my %synonym;
  if ($synonyms) {
	 %synonym = map {$_->value, $_} @$synonyms;
  }
  if ( $db_n && $db_n ne $n) {
	 if (!exists $synonym{$db_n}){
		my $obj_attributes=[];
		my $syn_attrib=$self->make_Attribute('synonym','Synonym','',$db_n);
		push @$obj_attributes,$syn_attrib;
		$obj->add_Attributes(@$obj_attributes);
	 }
  }

}

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


1;
__END__

=head1 NAME - Bio::Vega::DBSQL::GeneAdaptor

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
