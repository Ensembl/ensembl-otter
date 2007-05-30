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
    my ($self, $gene, $on_whole_chromosome) = @_;

    my $ga = $self->db->get_GeneAdaptor;
    my $ta = $self->db->get_TranscriptAdaptor;
    my $ea = $self->db->get_ExonAdaptor;
    my $sa = $self->db->get_StableIdAdaptor();

    if(my $gene_stid = $gene->stable_id()) {
        $gene->last_db_version( $ga->fetch_last_version($gene, $on_whole_chromosome) );
    } else {
        $gene->stable_id($sa->fetch_new_gene_stable_id);
    }

    foreach my $transcript (@{$gene->get_all_Transcripts}) {
        my $db_transcript;
        if(my $transcript_stid = $transcript->stable_id() ) {
            $transcript->last_db_version( $db_transcript = $ta->fetch_last_version($transcript, $on_whole_chromosome) );
        } else {
            $transcript->stable_id($sa->fetch_new_transcript_stable_id);
        }

        if (my $translation = $transcript->translation()) {

            if(my $translation_stid = $translation->stable_id()) {
                if($db_transcript) {
                    $translation->last_db_version( $db_transcript->translation() );
                }
            } else {
                $translation->stable_id($sa->fetch_new_translation_stable_id);
            }
        }
    }

        # since we ask for exons OF A GENE, we get them without repetition
        # (the uniqueness is taken care of by means of hashing them in Bio::EnsEMBL::Gene)
        #
    foreach my $exon (@{$gene->get_all_Exons}) {
        if(my $exon_stid = $exon->stable_id()) {
            $exon->last_db_version( $ea->fetch_last_version($exon, $on_whole_chromosome) );
        } else {
            $exon->stable_id($sa->fetch_new_exon_stable_id)
        }
    }
}

sub translations_diff {
  my ($self,$transcript)=@_;

  my $translation_changed=0;

  if(my $translation=$transcript->translation()) {
    if (my $db_translation=$translation->last_db_version()) {
        my $created_time = $db_translation->created_date();
        my $db_version   = $db_translation->version();

        if ($db_translation->stable_id ne $translation->stable_id) {
            print STDERR "Translations being compared have different stable_ids: '".$db_translation->stable_id."' and '".$translation->stable_id."'\n";
            #
            ##Remember to uncomment this after loading and remove the line/s after
            #	throw('translation stable_ids of the same two transcripts are different\n');
            #
            my $existing_translation=$self->db->get_TranslationAdaptor->fetch_by_stable_id($translation->stable_id);
            if($existing_translation){
                throw ("new translation stable_id(".$translation->stable_id.") for this transcript(".$transcript->stable_id().") is already associated with another transcript");
            } else { # NEW, but with a given stable_id
                $db_version          = 0;
                $translation_changed = 1;
            }
        } else {
            $translation_changed = compare($db_translation,$translation);
        }

        $translation->created_date($db_translation->created_date());
        $translation->modified_date($translation_changed ? $self->current_time : $created_time );
        $translation->version($db_version+$translation_changed);
    } else { # NEW
        $translation->created_date($self->current_time());
        $translation->modified_date($self->current_time());
        $translation->version(1);
        $translation_changed = 1;
    }
  }

  return $translation_changed;
}

sub exons_diff {
  my ($self, $exons, $shared_exons)=@_;

  my $any_exon_changed=0;

  foreach my $exon (@$exons){

    my $exon_changed = 0;

	if(my $db_exon=$exon->last_db_version()) { # non-NEW
        if($db_exon->is_current()) { # either CHANGED or UNCHANGED

            if($exon_changed=compare($db_exon,$exon)) {
                $exon->version($db_exon->version+1);
                $exon->created_date($db_exon->created_date);
                $exon->modified_date($self->current_time);

                $exon->is_current(1);
                $db_exon->is_current(0);
            } else { ## reuse the exon
                $exon=$db_exon;
            }
        } else { # RESTORED or SHARED
            ##restored exon or a currently shared exon of the transcripts of the same gene 
            ##which has changed and hence deleted by a previous transcript <---- ??? (lg4)

		  if (exists $shared_exons->{$exon->stable_id}){ # SHARED
			 $exon=$shared_exons->{$exon->stable_id};
		  } else { # RESTORED
			 $exon->created_date($db_exon->created_date);

			 ##check to see if the restored exon has changed
			 if($exon_changed=compare($db_exon,$exon)) {
				 $exon->version($db_exon->version+1);
				 $exon->modified_date($self->current_time);
			 } else {
                 $exon->version($db_exon->version);
				 $exon->modified_date($db_exon->modified_date());
             }
		  }
          $exon->is_current(1);
        }
    } else { # NEW
        $exon->version(1);
        $exon->created_date($self->current_time);
        $exon->modified_date($self->current_time);
        $exon->is_current(1);
    }

    ## maintain a distinct list of all exons of all transcripts of the gene
    if (! exists $shared_exons->{$exon->stable_id}){
        $shared_exons->{$exon->stable_id}=$exon;
    }

    $any_exon_changed ||= $exon_changed;

  }
  return $any_exon_changed;
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
      my $key = $start_exon->hashkey();
      ($start_exon) = grep {$_->hashkey() eq $key} @$exons;
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
      my $key = $end_exon->hashkey();
      ($end_exon) = grep {$_->hashkey() eq $key} @$exons;
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
  my $any_transcript_changed=0;
  my $shared_exons = {};
  foreach my $tran (@{ $gene->get_all_Transcripts }) {

        ##check if exons are new or old and if old whether they have changed or not:
	my $exons_changed = $self->exons_diff( $tran->get_all_Exons(), $shared_exons);

        # has to be run exactly once, so not suitable as a part of '||' expression:
    my $translation_changed = $self->translations_diff($tran);

	my $transcript_changed=0;

    if(my $db_transcript=$tran->last_db_version()) { # the transcript is not NEW

            # this is the check of 'significant change in structure':
        $transcript_changed = $exons_changed || $translation_changed || compare($db_transcript,$tran);

            # if the transcript is being restored, it is changed, too:
        $transcript_changed ||= ! $db_transcript->is_current();

            # deletion seems to happen in a different way from gene's deletion,
            # so we do not check it here.

        $tran->created_date($db_transcript->created_date);

        if($transcript_changed) {
            $self->compare_synonyms_add($db_transcript,$tran);
            $tran->version($db_transcript->version+1);
            $tran->modified_date($self->current_time);

            $tran->is_current(1);
        } else {
            $tran->version($db_transcript->version);
            $tran->modified_date($db_transcript->modified_date());

                ##retain old author:
            $tran->transcript_author($db_transcript->transcript_author);
        }

    } else { # no db_transcript means the transcript is NEW

        $tran->version(1);
        $tran->created_date($self->current_time);
        $tran->modified_date($self->current_time);
        $tran->is_current(1);
    }

    $any_transcript_changed ||= $transcript_changed;

    $self->check_start_and_end_of_translation($tran);
  }

  return $any_transcript_changed;
}

1;

__END__

=head1 NAME - Bio::Vega::AnnotationBroker

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
