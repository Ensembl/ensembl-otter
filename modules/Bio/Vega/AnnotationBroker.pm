package Bio::Vega::AnnotationBroker;

use strict;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);
#use base 'Bio::Vega::DBSQL::GeneAdaptor';
use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';

sub current_time {
  my ($self,$time)=@_;
  if (defined $time){
	 $self->{current_time}=$time;
  }
  return $self->{current_time};
}


sub find_update_deleted_transcripts_status {
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

sub find_update_deleted_exons_status {
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

sub translation_diff {
  my ($self,$sida,$transcript,$db_transcript)=@_;

  my $translation    = $transcript    && $transcript   ->translation();
  my $db_translation = $db_transcript && $db_transcript->translation();

  my $translation_changed=0;

  if($translation) {
	unless ($translation->stable_id) {
		$translation->stable_id($sida->fetch_new_translation_stable_id);
		$translation->version(1);
	}

    my ($created_time, $db_version);

    if ($db_translation) {
        $created_time = $db_translation->created_date();
        $db_version   = $db_translation->version();

        if ($db_translation->stable_id ne $translation->stable_id) {
            #Remember to uncomment this after loading and remove the line/s after
            #	throw('translation stable_ids of the same two transcripts are different\n');
            my $translation_adaptor=$self->db->get_TranslationAdaptor;
            my $not_good_and_new_translation=$translation_adaptor->fetch_by_stable_id($translation->stable_id);
            if($not_good_and_new_translation){
              throw ("new translation stable_id for this transcript is already associated with someother gene's transcript");
            }
            $db_version          = 0;
            $translation_changed = 1;
        } else {
            $translation_changed = compare($db_translation,$translation);
        }
    } else {
        $created_time        = $self->current_time();
        $db_version          = 0;
        $translation_changed = 1;
    }

    $translation->created_date($created_time);
    $translation->modified_date($translation_changed ? $self->current_time : $created_time );
    $translation->version($db_version+$translation_changed);

  } elsif($db_translation) { # translation disappeared
    $translation_changed=1;
  }

  return $translation_changed;
}

sub exons_diff {
  my ($self,$sida,$method_chooser,$exons,$shared)=@_;
  my $exon_changed=0;
  my $ea=$self->db->get_ExonAdaptor;
  ##check if exon is new or old
  foreach my $exon (@$exons){
	 ##assign stable_id for new exon
	 unless ($exon->stable_id) {
		$exon->stable_id($sida->fetch_new_exon_stable_id);
	 }

	 my $db_exon;
	 if ($method_chooser eq 'chr_gene_slice') {
		$db_exon=$ea->get_current_Exon_by_slice($exon);
	 }
	 elsif ($method_chooser eq 'chr_whole_slice') {
		$db_exon=$ea->fetch_by_stable_id($exon->stable_id);
	 }
	 if ( $db_exon){
		my $db_version=$db_exon->version;
      $exon_changed=compare($db_exon,$exon);
		##if exon has changed then increment version
		if ($exon_changed == 1){
		  $db_exon->is_current(0);
		  $ea->update($db_exon);
		  $exon->version($db_version+1);
		  $exon->is_current(1);
		  unless ($exon->modified_date){
			 $exon->modified_date($self->current_time);
		  }
		  $exon->created_date($db_exon->created_date);


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
		  unless ($exon->modified_date){
			 $exon->modified_date($self->current_time);
		  }
		  unless ($exon->created_date){
			 $exon->created_date($self->current_time);
		  }

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
			 my $old_exon;
			 if ($method_chooser eq 'chr_gene_slice'){
				$old_exon=$ea->get_deleted_Exon_by_slice($exon,$old_version);
			 }
			 elsif ($method_chooser eq 'chr_whole_slice') {
				$old_exon=$ea->fetch_by_stable_id_version($exon->stable_id,$old_version);
			 }
			 $exon->created_date($old_exon->created_date);
			 unless ($exon->modified_date){
				$exon->modified_date($self->current_time);
			 }
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

sub compare_synonyms_add{
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

sub check_for_change_in_gene_components {
  ## check if any of the gene component (transcript,exons,translation) has changed
  my ($self,$sida,$gene,$method_chooser,$time) = @_;

  $self->current_time($time);
  my $ta=$self->db->get_TranscriptAdaptor;
  my $tran_change_count=0;
  my $shared_exons_bet_txs;
  foreach my $tran (@{ $gene->get_all_Transcripts }) {
	 ##assign stable_id for new trancript
	 unless ($tran->stable_id) {
		$tran->stable_id($sida->fetch_new_transcript_stable_id);
	 }
	 ##check if exons are new or old and if old whether they have changed or not
	 my $exons=$tran->get_all_Exons;
	 my $exon_changed=0;
	 ($exon_changed,$shared_exons_bet_txs)=$self->exons_diff($sida,$method_chooser,$exons,$shared_exons_bet_txs);
	 ##check if translation has changed
	 ##only a partial chromosome slice is constructed when genes are saved through xml, from the otter lace client from the 
    ##sequence_fragment tags.But in case of external loading when sequence fragments are not know only a complete chromosome slice 
    ##be constructed from the sequence_set name.So the methods differ

	 my $db_transcript = ($method_chooser eq 'chr_gene_slice')
        ? $ta->get_current_Transcript_by_slice($tran)
        : $ta->fetch_by_stable_id($tran->stable_id);

	 my $translation_changed=$self->translation_diff($sida,$tran,$db_transcript);

	 ##check if transcript is new or old
	 ##if transcript is old compare to see if transcript has changed
	 my $transcript_changed=0;

	 $tran->is_current(1);
	 if($db_transcript) {
		$tran->created_date($db_transcript->created_date);

		$transcript_changed = $exon_changed || $translation_changed || compare($db_transcript,$tran);

        unless($tran->modified_date) {
            $tran->modified_date( $transcript_changed
                ? $self->current_time
                : $db_transcript->modified_date()
            );
        }

		$db_transcript->is_current(0);
		$ta->update($db_transcript);

		my $db_version=$db_transcript->version;

		##if transcript has changed then increment version
		if ($transcript_changed ) {
		  $tran->version($db_version+1);
		  ##add for transcript synonym
		  $self->compare_synonyms_add($db_transcript,$tran);
		}
		else {
		  $tran->version($db_version);
		  ##retain old author
		  $tran->transcript_author($db_transcript->transcript_author);
		}	
	 }
	 ##if transcript is new
	 else {
		my $restored_transcripts=$ta->fetch_all_versions_by_stable_id($tran->stable_id);
		if (!@$restored_transcripts){
		  $tran->version(1);
		  unless ($tran->modified_date){
			 $tran->modified_date($self->current_time);
		  }
		  unless ($tran->created_date){
			 $tran->created_date($self->current_time);
		  }
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
		  my $old_transcript;
		  if ($method_chooser eq 'chr_gene_slice'){
			 $old_transcript=$ta->get_deleted_Transcript_by_slice($tran,$old_version);
		  }
		  elsif ($method_chooser eq 'chr_whole_slice'){
			 $old_transcript=$ta->fetch_by_stable_id_version($tran->stable_id,$old_version);
		  }
		  $tran->created_date($old_transcript->created_date);
		  unless ($tran->modified_date){
			 $tran->modified_date($self->current_time);
		  }
		  my $old_translation=$old_transcript->translation;
		  $translation_changed=$self->translation_diff($sida,$tran,$old_transcript);
		  $transcript_changed=compare($old_transcript,$tran);
		  if ($exon_changed == 1 || $translation_changed == 1) {
			 $transcript_changed = 1;
		  }
		  if ($transcript_changed == 1){
			 $tran->version($old_version+1);
			 ##add for transcript synonym
			 $self->compare_synonyms_add($old_transcript,$tran);
		  }
		}
	 }
	 if ($transcript_changed == 1) {
		$tran_change_count++;
	 }
	 ##check to see if the start_Exon,end_Exon has been assigned right after comparisons
	 ##this check is needed since we reuse exons
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
			 ($start_exon) = grep {$_->stable_id eq $translation->start_Exon->stable_id} @$exons;
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
			 ($end_exon) = grep {$_->stable_id eq $translation->end_Exon->stable_id} @$exons;
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



1;
__END__

=head1 NAME - Bio::Vega::AnnotationBroker

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
