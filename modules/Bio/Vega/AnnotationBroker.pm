package Bio::Vega::AnnotationBroker;

use strict;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);
use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';

sub current_time {
  my ($self,$time)=@_;
  if (defined $time){
	 $self->{current_time}=$time;
  }
  return $self->{current_time};
}

    # This is an essential subroutine that takes care of two things at once:
    # 1. Gene components with no stable_ids get new ones
    # 2. Gene components with existing stable_ids get the latest db component
    #    with the same stable_id pre-loaded for later comparison.
    #
sub fetch_new_stable_ids_or_prefetch_latest_db_components {
    my ($self, $gene) = @_;

    my $ga = $self->db->get_GeneAdaptor;
    my $ta = $self->db->get_TranscriptAdaptor;
    my $ea = $self->db->get_ExonAdaptor;
    my $sa = $self->db->get_StableIdAdaptor();

    if (my $gene_stid = $gene->stable_id()) {
        $gene->last_db_version( $ga->fetch_latest_by_stable_id($gene_stid) );
    } else {
        $gene->stable_id($sa->fetch_new_gene_stable_id);
    }

        # to prevent identical exons (which are shared in DB but not in memory)
        # from getting different stable_ids
    my %exon_key_2_stable_id = ();

    foreach my $transcript (@{$gene->get_all_Transcripts}) {
        if(my $transcript_stid = $transcript->stable_id() ) {
            $transcript->last_db_version( $ta->fetch_latest_by_stable_id($transcript_stid) );
        } else {
            $transcript->stable_id($sa->fetch_new_transcript_stable_id);
        }

        if (my $translation = $transcript->translation()) {

            unless ($translation->stable_id()) {
                $translation->stable_id($sa->fetch_new_translation_stable_id);
            }
        }
    }

        # since we ask for exons OF A GENE, we get them without repetition
        # (the uniqueness is taken care of by means of hashing them in Bio::EnsEMBL::Gene)
        #
    foreach my $exon (@{$gene->get_all_Exons}) {
        if(my $exon_stid = $exon->stable_id()) {
            $exon->last_db_version( $ea->fetch_latest_by_stable_id($exon_stid) );
        } else {
            $exon->stable_id($sa->fetch_new_exon_stable_id)
        }
    }

}

sub translations_diff {
  my ($self,$transcript)=@_;

  my $translation_any_changes = 0;
  my $translation_seq_changes = 0;

  if(my $translation=$transcript->translation()) {
    my $db_transcript = $transcript->last_db_version();
    if ($db_transcript && (my $db_translation = $db_transcript->translation())) {
        my $created_time = $db_translation->created_date();
        my $db_version   = $db_translation->version();

        if ($db_translation->stable_id ne $translation->stable_id) {
            print STDERR "Translations being compared have different stable_ids: '"
                        .$db_translation->stable_id."' and '".$translation->stable_id."'\n";
            #
            ##Remember to uncomment this after loading and remove the line/s after
            #	throw('translation stable_ids of the same two transcripts are different\n');
            #
            
            my $existing_translation=$self->db->get_TranslationAdaptor->fetch_by_stable_id($translation->stable_id);
            if($existing_translation){
                throw ("new translation stable_id(".$translation->stable_id
                      .") for this transcript(".$transcript->stable_id()
                      .") is already associated with another transcript");
            } else { # NEW, but with a given stable_id
                $db_version              = 0;
                $translation_any_changes = 1;
                $translation_seq_changes = 1;
            }
        } else {
            $translation_any_changes = compare($db_translation, $translation)
                || ($db_transcript->translatable_Exons_vega_hashkey ne $transcript->translatable_Exons_vega_hashkey);

            if($translation_any_changes) {
                if((my $db_translate = $db_transcript->translate()) && (my $translate = $transcript->translate())) {
                    $translation_seq_changes = $db_translate->seq() ne $translate->seq();
                } else {
                    if(! $db_translate) {
                        warn "db_translate does not exist for ".$db_transcript->stable_id.'('.$db_transcript->dbID.')';
                        #die "db_translate does not exist for ".$db_transcript->stable_id.'('.$db_transcript->dbID.')';
                    } elsif(! $translate) {
                        warn "translate does not exist for ".$transcript->stable_id;
                        #die "translate does not exist for ".$transcript->stable_id;
                    }
                    $translation_seq_changes = 1; # to draw some attention!
                }
            }
        }

        $translation->created_date($db_translation->created_date());
        $translation->modified_date($translation_any_changes ? $self->current_time : $db_translation->modified_date );
        $translation->version($db_version + $translation_seq_changes);
    } else { # NEW
        $translation->created_date($self->current_time());
        $translation->modified_date($self->current_time());
        $translation->version(1);
        $translation_any_changes = 1;
        $translation_seq_changes = 1;
    }
  }

  return ($translation_any_changes, $translation_seq_changes);
}

sub exons_diff {
  my ($self, $transcript, $shared_exons) = @_;
  
  ### DANGER: This code depends on get_all_Exons() returning
  ### a ref to the actual list of exons in the object 
  my $actual_exon_list = $transcript->get_all_Exons;
  my $transl = $transcript->translation;
  
  ### Why pass in $shared_exons as an argument?  Shouldn't it be a property of the AnnotationBroker?

  my $exons_any_changes = 0;
  my $exons_seq_changes = 0;

  my $sa = $self->db->get_StableIdAdaptor();

  foreach my $exon (@$actual_exon_list) {

    my $save_exon = $exon;
    if (my $hashed_exon = $shared_exons->{$exon->stable_id}) {
        # we've seen it already in the new set
        if (compare($hashed_exon, $exon)) {
            # it's different, so split and find a new stable_id
            $exon->is_current(1);
            $exon->stable_id($sa->fetch_new_exon_stable_id);
            $exon->created_date($self->current_time);
            $exon->modified_date($self->current_time);
            $exon->version(1);
            $exons_any_changes = 1;
            $exons_seq_changes = 1; # could be, at least, as it is on the same seq_region as the hashed one
        } else {
            # just reuse it
            $hashed_exon->swap_slice($exon->slice);
            $exon = $hashed_exon;
        }
    }
    elsif (my $db_exon = $exon->last_db_version()) {
        # haven't seen yet, but it had a prev.version
        if (compare($db_exon, $exon)) {
            # the coords are different, make a new/old version
            $exon->is_current(1);
			$exon->created_date($db_exon->created_date);
            $exon->modified_date($self->current_time);

            # has the sequence of the exon changed?
            my $seq_diff = $db_exon->seq() ne $exon->seq();
            $exon->version($db_exon->version + $seq_diff);
            $exons_any_changes   = 1;
            $exons_seq_changes ||= $seq_diff;

        } else {
            # again, just reuse it
            $db_exon->swap_slice($exon->slice);
            $exon = $db_exon;
        }
    }
    else {
        # a completely new exon, but trust the stable_id we have
        $exon->version(1);
        $exon->created_date($self->current_time);
        $exon->modified_date($self->current_time);
        $exon->is_current(1);
        $exons_any_changes = 1; # a birth of a new exon is clearly a change :)
        $exons_seq_changes = 1; # including the change in the sequence
    }

    # maintain a set of all exons of all transcripts of the gene
    if (! $shared_exons->{$exon->stable_id}) {
        $shared_exons->{$exon->stable_id} = $exon;
    }
    
    # If we have used an exon from the database, we must
    # check to see if the translation uses it.
    if ($transl and $exon != $save_exon) {
        if ($save_exon == $transl->start_Exon) {
            $transl->start_Exon($exon);
        }
        if ($save_exon == $transl->end_Exon) {
            $transl->end_Exon($exon);
        }
    }
    
  }

  return ($exons_any_changes, $exons_seq_changes);
}

    # Because exons can be shared (potentially between genes!),
    # deleting them is a complex issue:
sub hide_unused_exons {
    my ($self, $db_genes, $stored_genes) = @_; # we need two lists of genes
                                               # (each list may contain just one or be empty)

    my %stored_exons_hash = ();
    foreach my $stored_gene (@$stored_genes) {
        foreach my $stored_exon (@{ $stored_gene->get_all_Exons() }) {
            $stored_exons_hash{$stored_exon->stable_id.'.'.$stored_exon->version} = $stored_exon;
        }
    }
    my %db_exons_hash = ();
    foreach my $db_gene (@$db_genes) {
        foreach my $dbexon (@{ $db_gene->get_all_Exons() }) {
            $db_exons_hash{$dbexon->stable_id.'.'.$dbexon->version} = $dbexon;
        }
    }
    my $exon_adaptor = $self->db->get_ExonAdaptor();
    while (my ($key, $dbexon) = each %db_exons_hash) {
        unless($stored_exons_hash{$key}) {
            $dbexon->is_current(0);
            $exon_adaptor->update($dbexon);
        }
    }
}

sub compare_synonyms_add {
    my ($self,$db_obj,$obj)=@_;

    my $db_name_attrib = $db_obj->get_all_Attributes('name');
    my $db_name = $db_name_attrib && $db_name_attrib->[0] && $db_name_attrib->[0]->value();

    my $name_attrib = $obj->get_all_Attributes('name');
    my $name = $name_attrib && $name_attrib->[0] && $name_attrib->[0]->value();

    if(!$db_name or ($db_name eq $name)) {
        return;
    }

    my %synonym =  map {$_->value, $_} @{ $obj->get_all_Attributes('synonym') };
    if (!exists $synonym{$db_name}){
        $obj->add_Attributes( $self->make_Attribute('synonym','Synonym','',$db_name) );
    }
}

sub make_Attribute {
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

	 ##check to see if the start_Exon,end_Exon has been assigned right after comparisons
	 ##this check is needed since we reuse exons
     #
sub check_start_and_end_of_translation {
    my ($self, $transcript) = @_;

    my $translation = $transcript->translation();

    unless($translation) {
        return 0;
    }

	my $exons=$transcript->get_all_Exons;

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
      my $key = $start_exon->vega_hashkey();
      ($start_exon) = grep {$_->vega_hashkey() eq $key} @$exons;
      if($start_exon) {
         $translation->start_Exon($start_exon);
      } else {
         ($start_exon) = grep {$_->stable_id eq $translation->start_Exon->stable_id} @$exons;
         if($start_exon) {
            $translation->start_Exon($start_exon);
         } else {
            throw("Translation's start_Exon does not appear to be one of the " .
                    "exons in its associated Transcript");
         }
      }
    }

    if(!$end_exon->dbID()) {
      my $key = $end_exon->vega_hashkey();
      ($end_exon) = grep {$_->vega_hashkey() eq $key} @$exons;
      if($end_exon) {
         $translation->end_Exon($end_exon);
      } else {
         ($end_exon) = grep {$_->stable_id eq $translation->end_Exon->stable_id} @$exons;
         if($end_exon) {
            $translation->end_Exon($end_exon);
         } else {
            throw("Translation's end_Exon does not appear to be one of the " .
                    "exons in its associated Transcript.");
         }
      }
    }

    return 1;
}

  ## check if any of the gene component (transcript,exons,translation) has changed
  #
sub transcripts_diff {
  my ($self, $gene, $time) = @_;

  $self->current_time($time);

  my $transcripts_any_changes = 0;
  my $transcripts_seq_changes = 0;

  my $shared_exons = {};
  foreach my $tran (@{ $gene->get_all_Transcripts }) {

        ## check if exons are new or old
        #  and if old whether they have changed or not:
        #  and if changed, was there any change in sequence?
    my ($exons_any_changes, $exons_seq_changes) = $self->exons_diff($tran, $shared_exons);

        # has to be run exactly once, so not suitable as a part of '||' expression:
    my ($translation_any_changes, $translation_seq_changes) = $self->translations_diff($tran);

	my $this_transcript_any_changes = 0;
    my $this_transcript_seq_changes = $exons_seq_changes || $translation_seq_changes;

    if(my $db_transcript=$tran->last_db_version()) { # the transcript is not NEW

            # this is the check of 'significant change in structure':
        $this_transcript_any_changes = $exons_any_changes || $translation_any_changes || compare($db_transcript,$tran);

            # if the transcript is being restored, it is changed, too:
        $this_transcript_any_changes ||= ! $db_transcript->is_current() || 0; # to get rid of undefs

            # deletion happens in GeneAdaptor, so just ignore it here

        $tran->created_date($db_transcript->created_date);

        if($this_transcript_any_changes) {
            $self->compare_synonyms_add($db_transcript,$tran);
            $tran->is_current(1);
            $tran->modified_date($self->current_time);

            $tran->version($db_transcript->version + $this_transcript_seq_changes );
        } else {
            $tran->modified_date($db_transcript->modified_date());

            $tran->version($db_transcript->version);

                ##retain old author:
            $tran->transcript_author($db_transcript->transcript_author);
        }

    } else { # no db_transcript means the transcript is NEW

        $tran->is_current(1);
        $tran->created_date($self->current_time);
        $tran->modified_date($self->current_time);
        $tran->version(1);

        $this_transcript_any_changes = 1; # because it should have its' own new exons
        $this_transcript_seq_changes = 1; # for the same reason
    }

    $transcripts_any_changes ||= $this_transcript_any_changes;
    $transcripts_seq_changes ||= $this_transcript_seq_changes;

    $self->check_start_and_end_of_translation($tran);
  }

  return ($transcripts_any_changes, $transcripts_seq_changes);
}

##################### SimpleFeature related subs ##############################

sub compare_feature_sets {
    my ($self, $old_features, $new_features) = @_;
    my %old = map { $self->SimpleFeature_key($_), $_ } @$old_features;
    my %new = map { $self->SimpleFeature_key($_), $_ } @$new_features;

    # Features that were in the old, but not the new, should be deleted
    my @delete = ();
    while (my ($key, $old_sf) = each %old) {
        unless ($new{$key}) {
            push(@delete, $old_sf);
        }
    }

    # Features that are in the new but were not in the old should be saved
    my @save = ();
    while (my ($key, $new_sf) = each %new) {
        unless ($old{$key}) {
            push(@save, $new_sf);
        }
    }
    return (\@delete, \@save);
}

sub SimpleFeature_key {
    my ($self, $sf) = @_;
    return join(
        '^',
        $sf->analysis->logic_name,
        $sf->start,
        $sf->end,
        $sf->strand,
        sprintf('%g', $sf->score),  # sprintf ensures that 0.5 and 0.5000 become the same string
        $sf->display_label || '',
    );
}

1;

__END__

=head1 NAME - Bio::Vega::AnnotationBroker

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
