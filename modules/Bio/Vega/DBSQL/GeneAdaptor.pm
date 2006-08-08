package Bio::Vega::DBSQL::GeneAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::Vega::Gene;
use Bio::Vega::Transcript;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);

use base 'Bio::EnsEMBL::DBSQL::GeneAdaptor';

sub fetch_by_stable_id  {

  my ($self, $stable_id) = @_;
  my ($gene) = $self->SUPER::fetch_by_stable_id($stable_id);
  if ($gene){
	 bless $gene, "Bio::Vega::Gene";
  }
  return $gene;

}
sub fetch_by_stable_id_version  {

  my ($self, $stable_id,$version) = @_;

  unless ($stable_id || $version) {
	 throw("Must enter a gene stable id:$stable_id and version:$version to fetch a Gene");
  }

  my $constraint = "gsi.stable_id = '$stable_id' AND gsi.version = '$version'";
  my ($gene) = @{ $self->generic_fetch($constraint) };
  bless $gene, "Bio::Vega::Gene";
  return $gene;

}

sub fetch_by_author {
}


sub check_for_change_in_gene_components {

  ## check if any of the gene component (transcript,exons,translation) has changed
  my ($self,$sida,$gene) = @_;
  my $transcripts=$gene->get_all_Transcripts;
  my $ta=$self->db->get_TranscriptAdaptor;
  my $tran_change_count=0;

  foreach my $tran (@$transcripts) {
	 ##assign stable_id for new trancript
	 unless ($tran->stable_id) {
		$sida->fetch_new_stable_ids_for_Transcript($tran);
	 }
	 ##check if exons are new or old and if old whether they have changed or not
	 my $exons=$tran->get_all_Exons;
	 my $exon_changed=0;
	 $exon_changed=$self->exons_diff($sida,$exons);

	 ##check if translation has changed
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
		#die "transcript hanged\n";
		}
		$db_transcript->is_current(0);
		$ta->update($db_transcript);

		##if transcript has changed then increment version
		if ($transcript_changed==1 ) {
		  $tran->version($db_version+1);
		}
		##if transcript has not changed then retain the same old version
		else {
		  $tran->version($db_version);
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
		  my $old_transcript=$ta->fetch_by_stable_id_version($tran->stable_id,$old_version);
		  my $old_translation=$old_transcript->translation;
		  $translation_changed=$self->translation_diff($sida,$tran,$old_transcript);
		  $transcript_changed=compare($old_transcript,$tran);
		  if ($exon_changed == 1 || $translation_changed == 1) {
			 $transcript_changed = 1;
		  }
		  if ($transcript_changed == 1){
			 $tran->version($old_version+1);

		  }
		}
	 }
	 if ($transcript_changed == 1) {
		$tran_change_count++;
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
		$sida->fetch_new_stable_ids_for_Translation($translation);
		$translation->version(1);
	 }
  }
  if (!$db_translation && $translation){
	 $translation->version(1);
	 $translation_changed=1;
	 return 1;
  }
  if (!$translation && $db_translation){
	 $translation_changed=1;
	 return 1;
  }
  if (defined $db_translation && $translation){
	 if ($db_translation->stable_id ne $translation->stable_id) {
		throw('translation stable_ids of the same two transcripts are different\n');
	 }
	 else {
		$translation_changed=compare($db_translation,$translation);
	 }

	 my $db_version=$db_translation->version;
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

  my ($self,$sida,$exons)=@_;
  my $exon_changed=0;
  my $ea=$self->db->get_ExonAdaptor;
  ##check if exon is new or old
  foreach my $exon (@$exons){
	 ##assign stable_id for new exon
	 unless ($exon->stable_id) {
		$sida->fetch_new_stable_ids_for_Exon($exon);
	 }
	 my $db_exon=$ea->fetch_by_stable_id($exon->stable_id);
	 ##if exon is old compare to see if anything has changed
	 if ( $db_exon){
		my $db_version=$db_exon->version;
      $exon_changed=compare($db_exon,$exon);
		##if exon has changed then increment version
		$db_exon->is_current(0);
		$ea->update($db_exon);

		if ($exon_changed == 1){
		  $exon->version($db_version+1);
		  $exon->is_current(1);
		}
		##if exon has not changed then retain the same old version
		else {
		  $exon->version($db_version);
		  $exon->is_current(1);
		}
	 }
	 ##if exon is new
	 else {
		my $restored_exons=$ea->fetch_all_versions_by_stable_id($exon->stable_id);
		if (@$restored_exons == 0){
		  $exon->version(1);
		  $exon->is_current(1);
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
		  my $old_exon=$ea->fetch_by_stable_id_version($exon->stable_id,$old_version);
		  $exon_changed=compare($old_exon,$exon);
		  if ($exon_changed == 1){
			 $exon->version($old_version+1);
		  }
		}
	 }
  }
  return $exon_changed;
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

   my ($self,$gene) = @_;
	$self->db->begin_work;
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
	unless ($gene->slice->adaptor){
	  $gene->slice->adaptor($sa);
	}

	##new gene - assign stable_id
	my $sida = $self->db->get_StableIdAdaptor();
	unless ($gene->stable_id){
	  $sida->fetch_new_stable_ids_for_Gene($gene);
	}
	##if gene is old compare to see if gene components have changed
	my $gene_changed=0;
	##check if gene is new or old

	my $db_gene=$self->fetch_by_stable_id($gene->stable_id);

	##deleted gene make sure is_current is set to 0

	my $type=$gene->biotype;

	if ( $type eq 'obsolete') {
	  if ($db_gene) {
		 $db_gene->is_current(0);
		 $self->update($db_gene);
		 $gene_changed = 5;
		 my $version=$db_gene->version;
		 $gene->version($version);
		 $gene->is_current(0);
		 my $transcripts=$gene->get_all_Transcripts;
		 my $ta=$self->db->get_TranscriptAdaptor;
		 foreach my $tran (@$transcripts) {
			unless ($tran->stable_id) {
			  throw('Trying to delete a transcript without a stable_id');
			}
			my $db_transcript=$ta->fetch_by_stable_id($tran->stable_id);
			my $version=$db_transcript->version;
			$tran->version($version);
			$tran->is_current(0);
			$db_transcript->is_current(0);
			$ta->update($db_transcript);
			my $translation=$tran->translation;
			if ($translation) {
			  my $db_translation=$db_transcript->translation;
			  unless ($db_translation || $translation->stable_id) {
				 throw('Trying to delete an unknown translation, either translation not in db or stable_id not set');
			  }
			  my $version=$db_translation->version;
			  $translation->version($version);
			}
		 }
		 my $ea=$self->db->get_ExonAdaptor;
		 my $exons=$gene->get_all_Exons;
		 foreach my $exon(@$exons){
			unless ($exon->stable_id){
			  throw('Trying to delete an exon without a stable_id');
			}
			my $db_exon=$ea->fetch_by_stable_id($exon->stable_id);
			my $version=$db_exon->version;
			$exon->version($version);
			$exon->is_current(0);
			$db_exon->is_current(0);
			$ea->update($db_exon);
		 }
	  }
	  else {
		 throw 'Trying to delete a gene that is already deleted OR Trying to delete a gene which is not present in database '.$gene->stable_id;
	  }
	}

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
		 $self->add_gene_synonym($db_gene,$gene);
	  }
	  else {
		 $gene->version($db_version);
	  }
	}
	my $old_gene;
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
			 $old_gene=$self->fetch_by_stable_id_version($gene->stable_id,$old_version);
			 $gene_changed=compare($old_gene,$gene);

			 if ($gene_changed == 1){

				$gene->version($old_version+1);
				##add synonym if old gene name is not a current gene synonym
				$self->add_gene_synonym($old_gene,$gene);
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

	if ($gene_changed == 1 || $gene_changed == 3 || $gene_changed == 5) {
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
	
	if ($gene_changed == 0) {
	  $self->db->rollback;
	  print STDOUT "\nUnchanged gene:".$gene->stable_id." Version:".$gene->version." nothing written in db\n";
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
	  $self->db->commit;
	  print STDOUT "\nChanged gene:".$gene->stable_id." Current Version:".$gene->version." changes stored successfully in db\n";

	}
	if ($gene_changed == 2) {
	  $self->db->commit;
	  print STDOUT "\nNew gene:".$gene->stable_id." Version:".$gene->version." stored successfully in db\n";
	}

	if ($gene_changed == 3) {
	  $self->db->commit;
	  print STDOUT "\nRestored gene:".$gene->stable_id." Version:".$gene->version." restored successfully in db\n";
	}
	
	if ($gene_changed == 5) {
	  $self->db->commit;
	  print STDOUT "\nDeleted gene:".$gene->stable_id." Version:".$gene->version." deleted successfully in db\n";
	}

 }

sub add_gene_synonym{
  my ($self,$db_gene,$gene)=@_;
  my $db_gene_name=$db_gene->get_all_Attributes('name');
  my $db_gn;
  if ($db_gene_name) {
	 if (defined $db_gene_name->[0]){
		$db_gn=$db_gene_name->[0]->value;
	 }
  }
  my $synonyms = $gene->get_all_Attributes('synonym');
  my $se=0;
  if (defined $synonyms && defined $db_gn) {
	 foreach my $syn (@$synonyms){
		if ($syn eq $db_gn){
		  $se=1;
		}
	 }
  }
  if ($se==0){
	 my $gene_attributes=[];
	 my $syn_attrib=$self->make_Attribute('synonym','Synonym','',$db_gn);
	 push @$gene_attributes,$syn_attrib;
	 $gene->add_Attributes(@$gene_attributes);
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
